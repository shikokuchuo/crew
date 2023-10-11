#' @title Local asynchronous client object.
#' @export
#' @family developer
#' @description Create an `R6` object to manage local asynchronous quick
#'   tasks with error detection.
#' @details [crew_async()] objects are created inside launchers to allow
#'   launcher plugins to run local tasks asynchronously, such as
#'   calls to cloud APIs to launch serious remote workers.
#' @return An `R6` async client object.
#' @param workers Number of local `mirai` daemons to run asynchronous tasks.
#'   If `NULL`, then tasks will be evaluated synchronously.
#' @examples
#' if (identical(Sys.getenv("CREW_EXAMPLES"), "true")) {
#' x <- crew_async()
#' x$start()
#' out <- x$eval(1 + 1)
#' mirai::call_mirai(out)
#' out$data # 2
#' x$errors() # 0
#' x$terminate()
#' }
crew_async <- function(workers = NULL) {
  async <- crew_class_async$new(workers = workers)
  async$validate()
  async
}

#' @title `R6` async class.
#' @export
#' @family class
#' @description `R6` class for async configuration.
#' @details See [crew_async()].
crew_class_async <- R6::R6Class(
  classname = "crew_class_async",
  cloneable = FALSE,
  public = list(
    #' @field workers See [crew_async()].
    workers = NULL,
    #' @field instance Character of length 1, name of the current instance.
    instance = NULL,
    #' @description TLS configuration constructor.
    #' @return An `R6` object with TLS configuration.
    #' @param workers Argument passed from [crew_async()].
    initialize = function(workers = NULL) {
      self$workers <- workers
    },
    #' @description Validate the object.
    #' @return `NULL` (invisibly).
    validate = function() {
      crew_assert(
        self$workers %|||% 57L,
        is.numeric(.),
        length(.) == 1L,
        !anyNA(.)
      )
      crew_assert(
        self$instance %|||% "x",
        is.character(.),
        length(.) == 1L,
        !anyNA(.),
        nzchar(.)
      )
      invisible()
    },
    #' @description Start the local workers and error handling socket.
    #' @details Does not create workers or an error handling socket
    #'   if `workers` is `NULL` or the object is already started.
    #' @return `NULL` (invisibly).
    start = function() {
      if (is.null(self$workers) || !is.null(self$instance)) {
        return(invisible())
      }
      self$instance <- crew::crew_random_name()
      mirai::daemons(
        n = self$workers,
        dispatcher = FALSE,
        .compute = self$instance
      )
      invisible()
    },
    #' @description Run a local asynchronous task using a local
    #'   compute profile.
    #' @details Used for launcher plugins with asynchronous launches and
    #'   terminations. If `processes` is `NULL`, the task will run locally.
    #'   Otherwise, the task will run on a local process in the local
    #'   `mirai` compute profile.
    #' @return If the `processes` field is `NULL`, a list with an object named
    #'   `data` containing the result of evaluating `expr` synchronously.
    #'   Otherwise, the task is evaluated asynchronously, and the result
    #'   is a `mirai` task object. Either way, the `data` element
    #'   of the return value will contain the result of the task.
    #' @param command R code to run.
    #' @param substitute Logical of length 1, whether to substitute `command`.
    #'   If `FALSE`, then `command` must be an expression object
    #'   or language object.
    #' @param data Named list of data objects required to run `command`.
    #' @param packages Character vector of packages to load.
    #' @param library Character vector of library paths to load the packages
    #'   from.
    eval = function(
      command,
      substitute = TRUE,
      data = list(),
      packages = character(0L),
      library = NULL
    ) {
      command <- if_any(substitute, substitute(command), command)
      if_any(
        is.null(self$workers),
        list(
          data = crew_eval_async(
            command = command,
            data = data,
            packages = packages,
            library = library
          )
        ),
        mirai::mirai(
          .expr = expr_crew_eval_async,
          command = command,
          data = data,
          packages = packages,
          library = library,
          url = self$url,
          .compute = self$instance
        )
      )
    },
    #' @description Start the local workers and error handling socket.
    #' @details Waits for existing tasks to complete first.
    #' @return `NULL` (invisibly).
    terminate = function() {
      if (is.null(self$workers) || is.null(self$instance)) {
        return(invisible())
      }
      mirai::daemons(n = 0L, .compute = self$instance)
      self$instance <- NULL
      invisible()
    }
  )
)

#' @title Run an asynchronous task in the crew launcher.
#' @description Called internally, not for users.
#' @export
#' @family utilities
#' @keywords internal
#' @return The result of running `command`.
#' @param command Language object with R code to run.
#' @param data Named list of objects that `command` depends on.
#' @param packages Character vector of packages to load.
#' @param library Character vector of library paths to load the packages from.
crew_eval_async <- function(
  command,
  data = list(),
  packages = character(0L),
  library = NULL
) {
  load_packages(packages = packages, library = library)
  eval(expr = command, envir = list2env(data, parent = globalenv()))
}

expr_crew_eval_async <- quote(
  crew::crew_eval_async(
    command = command,
    data = data,
    packages = packages,
    library = library
  )
)