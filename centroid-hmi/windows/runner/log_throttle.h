#ifndef RUNNER_LOG_THROTTLE_H_
#define RUNNER_LOG_THROTTLE_H_

#include <string>

// Rate limiting for diagnostic lines that can repeat at frame rate.
//
// The incident this exists for: a lost EGL context makes the engine fail every
// frame and log two ERROR lines each time, forever. One 36-minute freeze put
// 9.7 MB into the app log that way, and every byte of it said the same thing.
// Instrumenting the watchdog's own decision path -- which is what makes the
// next occurrence diagnosable at all -- would repeat that mistake at a
// different address unless every emitter is bounded from the start.
//
// The shape chosen is "loud, then quiet, then periodic":
//
//   * the first |burst| occurrences print in full, because the beginning of an
//     episode is the part worth reading;
//   * after that, one in every |every_nth|, so a long episode still shows
//     progress and timestamps;
//   * and regardless of count, at most one line per |summary_interval_ms|
//     carrying the number suppressed since the last one, so a reader can tell
//     "still happening, 4,102 times" from "stopped".
//
// Nothing here allocates per call and nothing here knows about a clock: the
// caller passes the time, which is also what makes it testable without one.

namespace tfc {

class LogThrottle {
 public:
  struct Config {
    // Occurrences printed verbatim at the start of an episode.
    int burst = 5;
    // After the burst, print one in every N.
    int every_nth = 100;
    // ...and never more often than this, whatever the count says.
    unsigned long long summary_interval_ms = 60000;
  };

  struct Decision {
    // Whether the caller should emit a line at all.
    bool emit = false;
    // How many occurrences were swallowed since the last emitted line. Zero on
    // the first |burst| lines; the point of the field is that a throttled line
    // can say "(+412 suppressed)" instead of pretending it is the only one.
    unsigned long long suppressed = 0;
    // The running total for this episode, including this occurrence.
    unsigned long long total = 0;
  };

  LogThrottle();
  explicit LogThrottle(Config config);

  // Records one occurrence and says whether to print it.
  Decision Record(unsigned long long now_ms);

  // Ends the episode: the next occurrence starts a fresh burst. Called when
  // the condition being counted has demonstrably stopped -- a frame was
  // presented, the engine was rebuilt -- so that a *second* episode is as
  // loud as the first rather than inheriting the first one's silence.
  void Reset();

  unsigned long long total() const { return total_; }
  // Occurrences seen since the last emitted line.
  unsigned long long suppressed() const { return suppressed_; }

  // "(+412 suppressed, 4102 total)", or an empty string when nothing was
  // suppressed. Suffix for a throttled line, so no reader mistakes a sampled
  // line for the only one.
  static std::string DescribeSuppression(const Decision& decision);

 private:
  Config config_;
  unsigned long long total_ = 0;
  unsigned long long suppressed_ = 0;
  unsigned long long last_emit_ms_ = 0;
  bool ever_emitted_ = false;
};

}  // namespace tfc

#endif  // RUNNER_LOG_THROTTLE_H_
