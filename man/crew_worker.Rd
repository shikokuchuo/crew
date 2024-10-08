% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/crew_worker.R
\name{crew_worker}
\alias{crew_worker}
\title{Crew worker.}
\usage{
crew_worker(
  settings,
  launcher,
  worker,
  instance,
  options_metrics = crew::crew_options_metrics()
)
}
\arguments{
\item{settings}{Named list of arguments to \code{mirai::daemon()}.}

\item{launcher}{Character of length 1, name of the launcher.}

\item{worker}{Positive integer of length 1, index of the worker.
This worker index remains the same even when the current instance
of the worker exits and a new instance launches.}

\item{instance}{Character of length 1 to uniquely identify
the current instance of the worker.}

\item{options_metrics}{Either \code{NULL} to opt out of resource metric logging
for workers, or an object from \code{\link[=crew_options_metrics]{crew_options_metrics()}} to enable
and configure resource metric logging for workers.}
}
\value{
\code{NULL} (invisibly)
}
\description{
Launches a \code{crew} worker which runs a \code{mirai} daemon.
Not a user-side function. Users should not call \code{\link[=crew_worker]{crew_worker()}}
directly. See launcher plugins like \code{\link[=crew_launcher_local]{crew_launcher_local()}}
for examples.
}
\seealso{
Other utility: 
\code{\link{crew_assert}()},
\code{\link{crew_clean}()},
\code{\link{crew_deprecate}()},
\code{\link{crew_eval}()},
\code{\link{crew_random_name}()},
\code{\link{crew_retry}()},
\code{\link{crew_terminate_process}()},
\code{\link{crew_terminate_signal}()}
}
\concept{utility}
