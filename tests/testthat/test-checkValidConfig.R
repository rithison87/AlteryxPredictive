context("checkValidConfig testing")

test_that("proper warning is returned for (and only for) < 5 numeric target vals", {
  the.data4 <- data.frame(y = rep(1:4, 100))
  the.data5 <- data.frame(y = rep(1:5, 100))
  names <- list(y = "y")
  config <- list(cp = .01)
  class(config) <- "OSR"
  expect_message(
    checkValidConfig(config, the.data4, names),
    "The target variable is numeric, however, it has 4 or fewer unique values."
  )
  expect_error(
    checkValidConfig(config, the.data5, names),
    NA
  )
})

test_that("proper error throwing is done for invalid control parameter", {
  the.data <- data.frame(y = 1:100)
  names <- list(y = "y")
  config0 <- list(cp = -0.1)
  config1 <- list(cp = 1.1)
  class(config0) <- class(config1) <- "OSR"
  expect_error(
    checkValidConfig(config0, the.data, names),
    "The complexity parameter must be between 0 and 1. Please try again."
  )
  expect_error(
    checkValidConfig(config1, the.data, names),
    "The complexity parameter must be between 0 and 1. Please try again."
  )
})
