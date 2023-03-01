#' @title Evaluate an R command and return results as a monad.
#' @export
#' @keywords internal
#' @description Not a user-side function. Do not call directly.
#' @return A monad object with results and metadata.
#' @param command Language object with R code to run.
#' @param envir Environment to run `command`.
#' @examples
#' crew_eval(quote(1 + 1))
crew_eval <- function(command, envir = parent.frame()) {
  force(envir)
  true(is.language(command))
  true(is.environment(envir))
  capture_error <- function(condition) {
    state$error <- crew_eval_message(condition)
    state$error_class <- class(condition)
    state$traceback <- paste(as.character(sys.calls()), collapse = "\n")
    NULL
  }
  capture_warning <- function(condition) {
    state$count_warnings <- (state$count_warnings %||% 0L) + 1L
    should_store_warning <- (state$count_warnings < crew_eval_max_warnings) &&
      (nchar(state$warnings %||% "") < crew_eval_max_nchar)
    if (should_store_warning) {
      state$warnings <- paste(
        c(state$warnings, crew_eval_message(condition)),
        collapse = ". "
      )
      state$warnings <- substr(
        state$warnings,
        start = 0,
        stop = crew_eval_max_nchar
      )
    }
    invokeRestart("muffleWarning")
  }
  state <- new.env(hash = FALSE, parent = emptyenv())
  start <- as.numeric(proc.time()["elapsed"])
  result <- tryCatch(
    expr = withCallingHandlers(
      expr = eval(expr = command, envir = envir),
      error = capture_error,
      warning = capture_warning
    ),
    error = function(condition) NULL
  )
  seconds <- as.numeric(proc.time()["elapsed"]) - start
  monad_init(
    command = deparse_safe(command),
    result = result,
    seconds = seconds,
    error = state$error %|||% NA_character_,
    traceback = state$traceback %|||% NA_character_,
    warnings = state$warnings %|||% NA_character_
  )
}

crew_eval_message <- function(condition, prefix = character(0)) {
  out <- crew_eval_text_substring(
    message = conditionMessage(condition),
    prefix = prefix
  )
  if_any(nzchar(out), out, ".")
}

crew_eval_text_substring <- function(message, prefix = character(0)) {
  tryCatch(
    substr(
      paste(c(prefix, message), collapse = " "),
      start = 0L,
      stop = crew_eval_max_nchar
    ),
    error = function(condition) {
      paste(
        "crew could not process the error or warning message",
        "due to a text encoding issue."
      )
    }
  )
}

crew_eval_max_nchar <- 2048L
crew_eval_max_warnings <- 51L