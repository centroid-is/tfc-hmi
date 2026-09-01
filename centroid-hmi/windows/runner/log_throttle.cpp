#include "log_throttle.h"

#include <sstream>

namespace tfc {

LogThrottle::LogThrottle() : LogThrottle(Config()) {}

LogThrottle::LogThrottle(Config config) : config_(config) {
  // A zero or negative every_nth would make the modulo below divide by zero
  // and take the process with it. A throttle that is asked for nonsense should
  // print more, never crash: 1 means "print everything after the burst".
  if (config_.every_nth < 1) {
    config_.every_nth = 1;
  }
  if (config_.burst < 0) {
    config_.burst = 0;
  }
}

LogThrottle::Decision LogThrottle::Record(unsigned long long now_ms) {
  total_++;

  Decision decision;
  decision.total = total_;

  const bool in_burst = total_ <= static_cast<unsigned long long>(config_.burst);

  // Sampling is counted from the end of the burst so that every_nth = 100
  // means "every hundredth after the loud ones", not "whenever the absolute
  // count happens to be divisible by a hundred" -- which, with a burst of 5,
  // would put the sixth printed line 95 occurrences after the fifth and every
  // one after that a round 100 apart. Same cadence either way in the long run;
  // this one is the one a reader can predict.
  const unsigned long long since_burst =
      in_burst ? 0 : total_ - static_cast<unsigned long long>(config_.burst);
  const bool sampled =
      !in_burst && (since_burst % static_cast<unsigned long long>(
                                     config_.every_nth) == 0);

  // The interval is a floor on *how often* a line may be printed, never a
  // reason to print one on its own: the caller only reaches Record when the
  // thing actually happened again. Its job is to stop a high every_nth from
  // still being loud when the underlying event fires thousands of times a
  // second -- which is exactly what a lost context does.
  const bool interval_elapsed =
      config_.summary_interval_ms == 0 ||  // no floor asked for
      !ever_emitted_ ||
      now_ms >= last_emit_ms_ + config_.summary_interval_ms;

  if (in_burst || (sampled && interval_elapsed)) {
    decision.emit = true;
    decision.suppressed = suppressed_;
    suppressed_ = 0;
    last_emit_ms_ = now_ms;
    ever_emitted_ = true;
  } else {
    suppressed_++;
  }

  return decision;
}

void LogThrottle::Reset() {
  total_ = 0;
  suppressed_ = 0;
  last_emit_ms_ = 0;
  ever_emitted_ = false;
}

std::string LogThrottle::DescribeSuppression(const Decision& decision) {
  if (decision.suppressed == 0) {
    return std::string();
  }
  std::ostringstream out;
  out << " (+" << decision.suppressed << " suppressed, " << decision.total
      << " total)";
  return out.str();
}

}  // namespace tfc
