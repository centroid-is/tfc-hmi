#include "stderr_interposer.h"

#include <fcntl.h>
#include <io.h>
#include <windows.h>

namespace tfc {
namespace {

// Generous. A storm writes ~6 KB/s; the buffer only has to cover reader
// thread scheduling hiccups, because a FULL pipe blocks every stderr writer
// in the process -- including the raster thread mid-error. Draining promptly
// is the reader's one hard obligation.
constexpr unsigned int kPipeBufferBytes = 1 << 20;

}  // namespace

bool StderrInterposer::Install(EglStormDetector::Config config,
                               StormCallback on_storm) {
  if (installed_) {
    return true;
  }

  int fds[2] = {-1, -1};
  if (_pipe(fds, kPipeBufferBytes, _O_BINARY | _O_NOINHERIT) != 0) {
    return false;
  }

  // Where stderr pointed until now; every byte is forwarded there. -1 when
  // there was no usable stderr (a GUI launch with nothing attached) -- then
  // there is nothing to forward to, but reading and detecting still work,
  // which is precisely the launch mode where the storm used to vanish into
  // nowhere.
  const int original = _dup(2);

  if (_dup2(fds[1], 2) != 0) {
    _close(fds[0]);
    _close(fds[1]);
    if (original != -1) {
      _close(original);
    }
    return false;
  }
  // fd 2 now owns a duplicate of the write end; the original descriptor for
  // it is redundant.
  _close(fds[1]);

  // Native writers (WriteFile on GetStdHandle) follow too. The CRT ones
  // already do via fd 2.
  ::SetStdHandle(STD_ERROR_HANDLE,
                 reinterpret_cast<HANDLE>(_get_osfhandle(2)));

  detector_ = EglStormDetector(config);
  on_storm_ = std::move(on_storm);
  pipe_read_fd_ = fds[0];
  original_stderr_fd_ = original;
  installed_ = true;

  reader_ = std::thread([this]() { ReaderLoop(); });
  // Process-lifetime: the thread ends when fd 2's last write end closes at
  // exit, and nothing joins it. Detaching is honest about that.
  reader_.detach();
  return true;
}

void StderrInterposer::ReaderLoop() {
  char buffer[8192];
  for (;;) {
    const int n = _read(pipe_read_fd_, buffer, sizeof(buffer));
    if (n <= 0) {
      return;
    }
    if (original_stderr_fd_ != -1) {
      // Best effort; a dead console must not stop the draining, or the pipe
      // fills and blocks the writers we are supposed to be observing.
      _write(original_stderr_fd_, buffer, static_cast<unsigned int>(n));
    }
    if (detector_.OnBytes(buffer, static_cast<std::size_t>(n),
                          ::GetTickCount64()) &&
        on_storm_) {
      on_storm_(detector_.matches_in_window());
    }
  }
}

}  // namespace tfc
