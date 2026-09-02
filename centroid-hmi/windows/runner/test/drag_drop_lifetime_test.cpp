// Tests for the drag-and-drop reference-count model behind the 2026-09-02
// crash.
//
// The minidump hmi-crash-20260902-165226-18448.dmp caught the platform thread
// in desktop_drop's DesktopDropPlugin destructor calling target_->Release()
// through a freed pointer -- a 0xC0000005 with an execute (DEP) sub-code --
// during the engine teardown that RebuildForSessionChange runs on an RDP
// reconnect. The process had already rebuilt once (a disconnect at 16:25:43)
// when the 16:52:26 reconnect rebuilt a second time and died.
//
// The root cause is that desktop_drop's OLE drop target balances its
// references exactly once per process, while the GPU watchdog destroys and
// recreates the FlutterViewController repeatedly. Without a revoke at teardown,
// a registration outlives its controller, the next rebuild re-registers on the
// reused child HWND and collides, and the reference count drifts. The fix --
// FlutterWindow::DestroyController revoking the child window's registration
// before dropping the controller -- keeps every rebuild balanced.
//
// These assert both directions: the pre-fix teardown leaks and collides, the
// fixed teardown stays balanced across many rebuilds.

#include "../drag_drop_lifetime.h"

#include "test_harness.h"

namespace {

using tfc::DragDropLifetimeModel;

constexpr bool kWithFix = true;
constexpr bool kNoFix = false;

// One create/destroy is the whole of a normal process lifetime. With the fix
// it is perfectly balanced; nothing leaks, nothing is freed twice.
TEST(single_lifecycle_is_balanced_with_the_fix) {
  DragDropLifetimeModel model(kWithFix);
  model.CreateController();
  model.DestroyController();
  CHECK(!model.use_after_free());
  CHECK(!model.registration_collision());
  CHECK_EQ(model.leaked_registrations(), 0);
  CHECK_EQ(model.live_targets(), 0);
}

// The pre-fix teardown never revoked, so even a single lifetime leaked the drop
// target's registration -- benign at process exit, but the seed of the crash
// once the engine is rebuilt.
TEST(single_lifecycle_leaks_without_the_fix) {
  DragDropLifetimeModel model(kNoFix);
  model.CreateController();
  model.DestroyController();
  CHECK_EQ(model.leaked_registrations(), 1);
}

// The crash precondition: rebuild the engine and the reused child HWND still
// carries the previous registration, so the next RegisterDragDrop collides and
// the reference count drifts.
TEST(rebuild_without_the_fix_collides_and_leaks) {
  DragDropLifetimeModel model(kNoFix);
  model.CreateController();   // initial engine
  model.DestroyController();  // RDP disconnect rebuild -- teardown 1
  model.CreateController();
  model.DestroyController();  // RDP reconnect rebuild -- teardown 2 (crashed)
  model.CreateController();

  CHECK(model.registration_collision());
  CHECK(model.leaked_registrations() > 0);
}

// The fix: revoke at teardown and every rebuild re-registers on a clean HWND,
// so nothing collides, nothing leaks, and no target is released after it is
// freed -- across far more rebuilds than any RDP session ever produces.
TEST(many_rebuilds_stay_balanced_with_the_fix) {
  DragDropLifetimeModel model(kWithFix);
  model.CreateController();
  for (int i = 0; i < 50; i++) {
    model.DestroyController();
    model.CreateController();
  }
  model.DestroyController();

  CHECK(!model.use_after_free());
  CHECK(!model.registration_collision());
  CHECK_EQ(model.leaked_registrations(), 0);
  CHECK_EQ(model.live_targets(), 0);
}

// The exact shape of the incident: one disconnect rebuild, then a reconnect
// rebuild. With the fix the second teardown -- the one that crashed -- is
// clean.
TEST(disconnect_then_reconnect_rebuild_is_clean_with_the_fix) {
  DragDropLifetimeModel model(kWithFix);
  model.CreateController();   // startup
  model.DestroyController();  // 16:25:43 WTS_REMOTE_DISCONNECT
  model.CreateController();
  model.DestroyController();  // 16:52:26 WTS_REMOTE_CONNECT (the crash)
  model.CreateController();

  CHECK(!model.use_after_free());
  CHECK(!model.registration_collision());
  CHECK_EQ(model.leaked_registrations(), 0);
}

// Destroying a controller that was never created must do nothing -- OnCreate
// can fail before CreateController, and Win32Window::Create runs a teardown on
// a window that does not exist yet.
TEST(destroy_without_create_is_a_no_op) {
  DragDropLifetimeModel model(kWithFix);
  model.DestroyController();
  CHECK(!model.use_after_free());
  CHECK_EQ(model.leaked_registrations(), 0);
  CHECK_EQ(model.live_targets(), 0);
}

}  // namespace

int main() { return tfc_test::RunAll(); }
