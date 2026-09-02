#ifndef RUNNER_DRAG_DROP_LIFETIME_H_
#define RUNNER_DRAG_DROP_LIFETIME_H_

// A pure-logic model of the Win32/OLE drag-and-drop reference-count lifecycle
// that the desktop_drop plugin drives, and that the GPU watchdog's engine
// create/destroy/recreate cycle runs MORE THAN ONCE per process.
//
// It exists to reproduce the 2026-09-02 crash and to prove the fix, the same
// way EglStormDetector and GpuWatchdog carry the logic the runner's Windows
// code only actuates. No I/O and no Windows headers, so it runs in the CTest
// suite on every platform. The one real OS call the fix needs -- one
// RevokeDragDrop in FlutterWindow::DestroyController -- is thin surgery that
// belongs with the window, exactly as StderrInterposer's fd work does; the
// reference-count reasoning it depends on lives here.
//
// --- The crash -------------------------------------------------------------
//
// The minidump hmi-crash-20260902-165226-18448.dmp caught the platform thread
// inside desktop_drop's DesktopDropPlugin destructor, at
//
//     mov  rcx,[rdi+8]        ; target_  (the DesktopDropTarget*)
//     mov  rax,[rcx]          ; target_'s vtable
//     call [rax+10h]          ; target_->Release()
//
// with target_ pointing at freed, recycled heap (its first qword pointed at
// itself), so the call dispatched into non-executable memory: a 0xC0000005
// access violation with an execute (DEP) sub-code. The plugin object itself
// was intact -- only target_ was a corpse. A use-after-free of the drop
// target, during engine teardown.
//
// --- Why it happens on the SECOND rebuild ----------------------------------
//
// desktop_drop's DesktopDropTarget is an OLE IDropTarget. Its lifetime is:
//
//   * constructor: RegisterDragDrop(view_hwnd, this) -- an AddRef (ref 0 -> 1),
//     and OLE records the target against the child HWND;
//   * plugin constructor: a second AddRef (ref 1 -> 2);
//   * plugin destructor: one Release;
//   * the target's own destructor (at ref 0): RevokeDragDrop(view_hwnd).
//
// That balances exactly once per process. But the GPU watchdog destroys and
// recreates the whole FlutterViewController -- on every RDP session change
// (RebuildForSessionChange) and on device-loss recovery -- so the register /
// revoke pair runs repeatedly. When a teardown does NOT revoke the child
// window's registration, the next controller re-registers on a child HWND that
// still carries the previous registration; that registration outlives its
// controller, the reference counts drift, and a target is freed one step early.
// The plugin destructor then releases through the dangling pointer.
//
// The crashed process had already rebuilt once (an RDP disconnect at 16:25:43)
// when the 16:52:26 reconnect rebuilt a second time and died.
//
// --- The fix ---------------------------------------------------------------
//
// FlutterWindow::DestroyController revokes the child window's registration
// before dropping the controller, while it still owns the view window. Every
// controller then revokes exactly what it registered: no registration outlives
// its controller, every AddRef has its Release, and the count stays balanced
// across any number of rebuilds. This model asserts precisely that invariant,
// and that the pre-fix teardown violates it.

#include <vector>

namespace tfc {

// Simulates the DesktopDropTarget reference count across the runner's
// controller lifecycle. |runner_revokes_on_teardown| is the fix.
class DragDropLifetimeModel {
 public:
  explicit DragDropLifetimeModel(bool runner_revokes_on_teardown)
      : runner_revokes_(runner_revokes_on_teardown) {}

  // The runner builds a FlutterViewController; desktop_drop registers a fresh
  // drop target on the child window. Windows reuses the child HWND across
  // recreated views, modelled here as the single registration slot.
  void CreateController();

  // The runner destroys the controller. With the fix it revokes the child
  // window's registration first; then the engine's plugin teardown releases
  // the plugin's own reference.
  void DestroyController();

  // Set once any Release touched a target whose reference count was already
  // zero: the use-after-free the minidump shows.
  bool use_after_free() const { return use_after_free_; }

  // Set once RegisterDragDrop was issued for a HWND that still carried a
  // registration -- the stale-registration collision that unbalances the count.
  bool registration_collision() const { return registration_collision_; }

  // Registrations that outlived the controller that created them. The fix
  // keeps this at zero; without it, it grows with every rebuild.
  int leaked_registrations() const { return leaked_registrations_; }

  // Drop-target objects allocated but never freed. Balanced teardown drains
  // this to zero after the final controller is destroyed.
  int live_targets() const;

 private:
  struct Target {
    int refcount = 0;
    bool freed = false;
  };

  int NewTarget();
  void AddRef(int index);
  void Release(int index);
  void Revoke();  // RevokeDragDrop(view_hwnd): release + clear the slot.

  bool runner_revokes_ = false;
  bool controller_up_ = false;
  bool use_after_free_ = false;
  bool registration_collision_ = false;
  int leaked_registrations_ = 0;

  std::vector<Target> targets_;
  int registered_index_ = -1;      // OLE's slot for the reused child HWND.
  int plugin_target_index_ = -1;   // target the live plugin holds.
};

}  // namespace tfc

#endif  // RUNNER_DRAG_DROP_LIFETIME_H_
