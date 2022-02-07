
# crew

<!--[![CRAN](https://www.r-pkg.org/badges/version/crew)](https://CRAN.R-project.org/package=crew)-->

[![status](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)
[![check](https://github.com/wlandau/crew/workflows/check/badge.svg)](https://github.com/wlandau/crew/actions?query=workflow%3Acheck)
[![codecov](https://codecov.io/gh/wlandau/crew/branch/main/graph/badge.svg?token=3T5DlLwUVl)](https://app.codecov.io/gh/wlandau/crew)
[![lint](https://github.com/wlandau/crew/workflows/lint/badge.svg)](https://github.com/wlandau/crew/actions?query=workflow%3Alint)

The [`R6`](https://r6.r-lib.org) classes of `crew` establish a
standardized user interface to high-performance computing technologies.
Unlike its closely related [`future`](https://future.futureverse.org/)
package, `crew` prioritizes centralized scheduling, heterogeneous
semi-persistent workers, and user-driven customization. The primary goal
is to help pipeline tools such as such
[`targets`](https://docs.ropensci.org/targets/) efficiently orchestrate
tasks without having to support individual low-level interfaces to
specific high-performance computing platforms or cloud services.

## Installation

``` r
remotes::install_github("wlandau/crew")
```

## Usage

First, create a `crew` object.

``` r
library(crew)
crew <- class_crew$new()
```

Optionally, supply the store and worker classes you plan to use. The
store determines where the input and output data live for jobs (local
file system, Amazon S3 bucket, Google Cloud bucket, etc.), and worker
classes control where and how the workers run (locally in a different R
session, Amazon Web Services, Google Cloud Platform, etc.).

``` r
crew <- class_crew$new(
  store = class_store_local$new(),
  worker_classes = list(
    class_worker_callr,
    class_worker_future
  )
)
```

If you use `class_worker_future`, choose a plan.

``` r
library(future)
library(future.callr)
plan(callr)
```

Create worker objects with the `recruit()` method.

``` r
crew$recruit(workers = 2) # callr workers
```

Optionally, create worker objects of a specified class and set fields
like timeout and tags.

``` r
names(crew$worker_classes)
#> [1] "worker_callr"  "worker_future"
crew$recruit(
  workers = 2,
  class = "worker_future",
  tags = c("long_jobs_go_here", "my_future_workers")
)
```

No workers are running yet.

``` r
library(purrr)
map_lgl(crew$workers, ~.x$up())
#> worker_e42926df1465 worker_e4297fb406d2 worker_e429665e3c55 worker_e42934cb24f4 
#>               FALSE               FALSE               FALSE               FALSE
```

To start any or all workers, either use `launch()` or `send()`. The
latter finds a suitable available worker, launches it if necessary, and
then sends a job. Poll with `receivable()` and get the output with
`receive()`. Tags let you control which kinds of workers get the jobs,
and they are are supported and optional in all relevant crew methods.

``` r
job <- function(seconds) {
  Sys.sleep(seconds)
  warning("This is a warning.")
  sprintf("Job ran in %s seconds.", seconds)
}

# The job runs on a worker of class "worker_future" in this case
# because those two workers are tagged with "long_jobs_go_here".
crew$send(fun = job, args = list(seconds = 4), tags = "long_jobs_go_here")

# Do other tasks while the job runs in the background.
do_other_tasks <- function () {
  start <- as.numeric(proc.time()["elapsed"])
  while (!crew$receivable()) {
    Sys.sleep(1)
    print(as.numeric(proc.time()["elapsed"]) - start)
  }
}

do_other_tasks()
#> [1] 1.003
#> [1] 2.012
#> [1] 3.013
#> [1] 4.015
#> [1] 5.016

# Get the output when ready.
output <- crew$receive()
```

The output contains the result of the job, as well as warnings, errors,
etc.

``` r
str(output)
#> List of 5
#>  $ value    : chr "Job ran in 4 seconds."
#>  $ seconds  : num 4
#>  $ error    : NULL
#>  $ traceback: NULL
#>  $ warnings : chr "This is a warning."
```

Once launched, workers stay running until they time out or shut down.

``` r
is_up <- map_lgl(crew$workers, ~.x$up())
is_up
#> worker_e42926df1465 worker_e4297fb406d2 worker_e429665e3c55 worker_e42934cb24f4 
#>               FALSE               FALSE                TRUE               FALSE
```

Sure enough, the running worker has the tags of the previous job.

``` r
name <- names(is_up[is_up])
crew$workers[[name]]$tags
#> [1] "long_jobs_go_here" "my_future_workers"
```

`crew` tries to send jobs to workers that are already running. If all
running workers are busy, new ones will launch automatically. Use
`sendable()` to check if any workers can accept new work.

``` r
crew$send(fun = job, args = list(seconds = 8), tags = "long_jobs_go_here")
crew$send(fun = job, args = list(seconds = 4)) # May run on any available worker.

do_other_tasks()
#> [1] 1.005
#> [1] 2.007
#> [1] 3.008
#> [1] 4.009
#> [1] 5.013

output_first <- crew$receive()

do_other_tasks()
#> [1] 1.001
#> [1] 2.004
#> [1] 3.004
#> [1] 4.01

output_second <- crew$receive()

str(output_first)
#> List of 5
#>  $ value    : chr "Job ran in 4 seconds."
#>  $ seconds  : num 4
#>  $ error    : NULL
#>  $ traceback: NULL
#>  $ warnings : chr "This is a warning."

str(output_second)
#> List of 5
#>  $ value    : chr "Job ran in 8 seconds."
#>  $ seconds  : num 8.02
#>  $ error    : NULL
#>  $ traceback: NULL
#>  $ warnings : chr "This is a warning."
```

To shut down one or more workers, use `shutdown()`. By default, only
idle workers are shut down.

``` r
crew$shutdown()
while (any(map_lgl(crew$workers, ~.x$up()))) {
  Sys.sleep(0.1)
}
```

To delete one or more worker objects from the crew, use `dismiss()`.

``` r
crew$dismiss(tags = "long_jobs_go_here")
length(crew$workers) # Should be 2.
#> [1] 2
```

If eventually a worker gets stuck (not sendable, not receivable, not
running) then the `stuck()` method of the worker will return `TRUE` and
the `restart()` method will restart it. Use the `restart()` method of
the crew object to restart one or more stuck workers.

## Nested crews

Large data science pipelines manage hundreds of distributed workers on
different machines, from traditional clusters to cloud platforms by
Amazon and Google. In these situations, orchestration itself is
computationally demanding. Sending jobs, receiving job output, and
detecting crashes may severely block the main process.

To overcome this bottleneck, `crew` package will eventually support
nested crews. The outer crew will support a small number of
`callr::r_bg()` workers running on the same machine as the main process.
Each of these outer workers will run a crew of its own, and the inner
crews will run hundreds of inner workers on distributed systems like AWS
Batch. The outer workers will run a different event loop that forwards
jobs from the outer crew to the inner crews and back.

## New backends

The `crew` package is arbitrarily extensible. It is designed to support
multiple backend services (e.g. Amazon, Google, Azure) with minimal
changes to the `R6` interface. For Amazon S3 storage for jobs, one can
write a new subclass of `class_store` and write methods analogous to
those of `class_store_local`. Likewise, for Amazon AWS Batch or Google
Cloud Run workers, one can write new worker subclasses analogous to
`class_worker_callr` and `class_worker_future`. All these classes are
documented in help files, and a specification of required methods and
fields is in the [specification
vignette](https://wlandau.github.io/crew/articles/specification.html).
The new subclasses will be supported in separate R packages that import
`crew`, ideally one package per cloud platform.

## Thanks

The `crew` package incorporates insightful ideas from the following
people.

-   [Kirill Müller](https://github.com/krlmlr/). The
    [`workers`](https://github.com/wlandau/worker) prototype was
    entirely his vision, and `crew` would not exist without it. `crew`
    reflects this and many other insights from Kirill about
    orchestration models for R processes.
-   [Henrik Bengtsson](https://github.com/HenrikBengtsson/). Henrik’s
    [`future`](https://github.com/HenrikBengtsson/future/) package
    ecosystem demonstrates the incredible power of a consistent R
    interface on top of a varying collection of high-performance
    computing technologies.
-   [Michael Schubert](https://github.com/mschubert/). Michael’s
    [`clustermq`](https://mschubert.github.io/clustermq/) package
    supports efficient high-performance computing on traditional
    clusters, and it demonstrates the value of a central `R6` object to
    manage an entire collection of persistent workers.
-   [David Kretch](https://github.com/davidkretch). The
    [`paws`](https://github.com/paws-r/paws) R package is a powerful
    interface to Amazon Web Services, and the documentation clearly
    communicates the capabilities and limitations of AWS to R users.
-   [Adam Banker](https://github.com/adambanker), co-authored
    [`paws`](https://github.com/paws-r/paws) with [David
    Kretch](https://github.com/davidkretch).
-   [David Neuzerling](https://github.com/mdneuzerling). David’s
    [`lambdr`](https://github.com/mdneuzerling/lambdr/) package
    establishes a helpful pattern to submit and collect AWS Lambda jobs
    from R.
-   [Mark Edmondson](https://github.com/MarkEdmondson1234/). Mark
    maintains several R packages to interface with Google Cloud Platform
    such as
    [`googleCloudStorageR`](https://github.com/cloudyr/googleCloudStorageR)
    and
    [`googleCloudRunner`](https://github.com/MarkEdmondson1234/googleCloudRunner),
    and he [started the
    conversation](https://github.com/ropensci/targets/issues/720) around
    helping [`targets`](https://github.com/ropensci/targets) submit jobs
    to Google Cloud Run.

## Code of Conduct

Please note that the `crew` project is released with a [Contributor Code
of
Conduct](https://github.com/wlandau/crew/blob/main/CODE_OF_CONDUCT.md).
By contributing to this project, you agree to abide by its terms.

## Citation

``` r
citation("crew")
#> 
#> To cite package 'crew' in publications use:
#> 
#>   William Michael Landau (NA). crew: Centralized Reusable Workers.
#>   https://wlandau.github.io/crew/, https://github.com/wlandau/crew.
#> 
#> A BibTeX entry for LaTeX users is
#> 
#>   @Manual{,
#>     title = {crew: Centralized Reusable Workers},
#>     author = {William Michael Landau},
#>     note = {https://wlandau.github.io/crew/, https://github.com/wlandau/crew},
#>   }
```
