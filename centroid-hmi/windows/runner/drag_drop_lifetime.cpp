#include "drag_drop_lifetime.h"

// See drag_drop_lifetime.h for the crash this reproduces and the fix it proves.
//
// Each step below mirrors a real behaviour:
//
//   NewTarget()        new DesktopDropTarget, reference count 0.
//   AddRef / Release   InterlockedIncrement / Decrement; Release frees at 0,
//                      and a Release of an already-freed target is the
//                      use-after-free the minidump caught.
//   Free()             delete this + ~DesktopDropTarget, which itself calls
//                      RevokeDragDrop(view_hwnd) -- so freeing a target can
//                      release whatever the child-window slot still holds.
//   CreateController() RegisterDragDrop AddRefs and records the target; on a
//                      slot that is already occupied it returns
//                      DRAGDROP_E_ALREADYREGISTERED and does NOT AddRef (the
//                      plugin does not handle that failure). The plugin then
//                      AddRefs a second reference.
//   DestroyController() with the fix, RevokeDragDrop first (release + clear the
//                      slot); then the engine's plugin teardown releases the
//                      plugin's own reference.

namespace tfc {

int DragDropLifetimeModel::NewTarget() {
  targets_.push_back(Target{});
  return static_cast<int>(targets_.size()) - 1;
}

void DragDropLifetimeModel::AddRef(int index) {
  if (index < 0) {
    return;
  }
  targets_[index].refcount++;
}

void DragDropLifetimeModel::Release(int index) {
  if (index < 0) {
    return;
  }
  if (targets_[index].freed) {
    // Release() dispatched through a vtable whose object is already gone: the
    // 0xC0000005 the crash dump shows.
    use_after_free_ = true;
    return;
  }
  if (--targets_[index].refcount <= 0) {
    targets_[index].freed = true;
    // ~DesktopDropTarget calls RevokeDragDrop(view_hwnd). If the child-window
    // slot still points at some OTHER target, OLE releases that one too; if it
    // points at the target being freed, OLE just drops the record (the object
    // is already dying, so it is not released again).
    if (registered_index_ == index) {
      registered_index_ = -1;
    } else if (registered_index_ != -1) {
      int occupant = registered_index_;
      registered_index_ = -1;
      Release(occupant);
    }
  }
}

void DragDropLifetimeModel::Revoke() {
  if (registered_index_ == -1) {
    return;
  }
  int occupant = registered_index_;
  registered_index_ = -1;
  Release(occupant);
}

void DragDropLifetimeModel::CreateController() {
  controller_up_ = true;

  int target = NewTarget();

  // DesktopDropTarget constructor: RegisterDragDrop(view_hwnd, this).
  if (registered_index_ == -1) {
    registered_index_ = target;
    AddRef(target);
  } else {
    // The child HWND is reused and its previous registration was never
    // revoked, so RegisterDragDrop fails and the fresh target goes un-AddRef'd.
    registration_collision_ = true;
  }

  // DesktopDropPlugin constructor: target_->AddRef().
  AddRef(target);
  plugin_target_index_ = target;
}

void DragDropLifetimeModel::DestroyController() {
  if (!controller_up_) {
    return;
  }

  // The fix: return the child window to a clean drag-and-drop state before the
  // engine tears its plugins down.
  if (runner_revokes_) {
    Revoke();
  }

  // Engine teardown: ~DesktopDropPlugin -> target_->Release().
  Release(plugin_target_index_);
  plugin_target_index_ = -1;
  controller_up_ = false;

  // The child window is destroyed, but a registration that was never revoked
  // outlives it -- the stale record that unbalances the next rebuild.
  if (registered_index_ != -1) {
    leaked_registrations_++;
  }
}

int DragDropLifetimeModel::live_targets() const {
  int live = 0;
  for (const Target& target : targets_) {
    if (!target.freed) {
      live++;
    }
  }
  return live;
}

}  // namespace tfc
