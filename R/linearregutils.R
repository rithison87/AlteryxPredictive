#' Process Linear Regression Inputs
#'
#' These two functions take `inputs` and `config` and return the model object
#' along with other elements essential to create the reports and plots
#'
#' @param inputs input data streams to the tool
#' @param config configuration passed to the tool
#' @rdname processLinear
#' @export
processLinearOSR <- function(inputs, config){
  var_names <- getNamesFromOrdered(names(inputs$the.data), config$`Use Weight`)
  the.formula <- if (config$`Omit Constant`){
    makeFormula(c("-1", var_names$x), var_names$y)
  } else {
    makeFormula(var_names$x, var_names$y)
  }
  # FIXME: Revisit what we pass to the weights argument.
  if (config$`Use Weight`){
    lm(the.formula, inputs$the.data, weights = inputs$the.data[[var_names$w]])
  } else {
    lm(the.formula, inputs$the.data)
  }
}

#' @inheritParams processLinearOSR
#' @rdname processLinear
#' @export
processLinearXDF <- function(inputs, config){
  temp.dir <- textInput('%Engine.TempFilePath%', tempdir())
  xdf.path = inputs$XDFInfo$xdf_path
  var_names <- getNamesFromOrdered(names(inputs$the.data), config$`Use Weight`)
  the.formula = if (config$`Omit Constant`){
    makeFormula(c("-1", var_names$x), var_names$y)
  } else {
    makeFormula(var_names$x, var_names$y)
  }
  the.model <- RevoScaleR::rxLinMod(the.formula, xdf.path, pweights = var_names$w,
    covCoef = TRUE, dropFirst = TRUE)

  # Add the level labels for factor predictors to use in model scoring, and
  # determine if the smearing estimator adjustment should be calculated for
  # scoring option value.
  the.model$xlevels <- getXdfLevels(makeFormula(var_names$x, ""), xdf.path)
  sum.info <- RevoScaleR::rxSummary(makeFormula(var_names$y, ""), xdf.path)
  # See if it is possible that the maximum target value is consistent with the
  # use of a natural log transformation, and construct the smearing adjust if
  # it is.
  if (sum.info$sDataFrame[1,5] <= 709) {
    resids.path <- file.path(temp.dir, paste0(ceiling(100000*runif(1)), '.xdf'))
    RevoScaleR::rxPredict(the.model, data = xdf.path, outData = resids.path,
      computeResiduals = TRUE, predVarNames = "Pred", residVarNames = "Resid")
    resids.df <- RevoScaleR::rxReadXdf(file = resids.path)
    smear <- RevoScaleR::rxSummary(~ Resid, data = resids.path,
      transforms = list(Resid = exp(Resid)))
    the.model$smearing.adj <- smear$sDataFrame[1,2]
  }
  return(the.model)
}

#' Convert data frame into a numeric matrix, filtering out non-numeric columns
#'
#' @param x data frame to coerce to a numeric matrix
df2NumericMatrix <- function(x){
  numNonNumericCols <- NCOL(Filter(Negate(is.numeric), x))
  if (numNonNumericCols == NCOL(x)){
    AlteryxMessage2("All of the provided variables were non-numeric. Please provide at least one numeric variable and try again.", iType = 2, iPriority = 3)
    stop.Alteryx2()
  } else if (numNonNumericCols > 0){
    AlteryxMessage2("Non-numeric variables were included to glmnet. They are now being removed.", iType = 1, iPriority = 3)
    x <- Filter(is.numeric, x)
  }
  x <- as.matrix(x)
  return(x)
}

#' Process Elastic Net Inputs
#'
#' This function takes `inputs` and `config` and returns the model object
#' along with other elements essential to create the reports and plots
#'
#' @param inputs input data streams to the tool
#' @param config configuration passed to the tool
#' @rdname processElasticNet
#' @export
#' @import glmnet
processElasticNet <- function(inputs, config){
  var_names <- getNamesFromOrdered(names(inputs$the.data), config$`Use Weights`)
  glmFun <- if (config$internal_cv) glmnet::cv.glmnet else glmnet::glmnet
  x <- df2NumericMatrix(inputs$the.data[,var_names$x])
  funParams <- list(x = x,
                    y = inputs$the.data[,var_names$y], family = 'gaussian',
                    intercept  = !(config$`Omit Constant`), standardize = config$standardize_pred, alpha = config$alpha,
                    weights = if (!is.null(var_names$w)) inputs$the.data[,var_names$w] else NULL,
                    nfolds = if (config$internal_cv) config$nfolds else NULL
  )
  #Set the seed for reproducibility (if the user chose to do so) in the internal-cv case
  if ((config$internal_cv) && (config$set_seed_internal_cv)) {
    set.seed(config$seed_internal_cv)
  }
  the.model <- do.call(glmFun, Filter(Negate(is.null), funParams))
  if (config$internal_cv) {
    #The predict function used with objects of class cv.glmnet can be
    #called with s = "lambda.1se" or s = "lambda.min" .
    if (config$lambda_1se) {
      the.model$lambda_pred <- "lambda.1se"
    } else {
      the.model$lambda_pred <- "lambda.min"
    }
  } else {
    #When the predict function is called with glmnet objects, it either
    #needs a specific value of lambda, or must be called with s= NULL,
    #in which case the predictions will be made at every lambda value in the sequence.
    the.model$lambda_pred <- config$lambda_no_cv
  }
  #Since glmnet and cv.glmnet don't produce a formula, we'll need to save the names
  #of the predictor variables in order to use getXvars downstream, which is required by
  #scoreModel.
  the.model$xvars <- colnames(x)
  return(the.model)
}

#' Create Reports
#'
#' If the ANOVA table is requested then create it and add its results to the
#' key-value table. Its creation will be surpressed if the car package isn't
#' present, or if the input is an XDF file.
#'
#' @param the.model model object
#' @param config configuration passed to the tool
#' @export
#' @rdname createReportLinear
createReportLinearOSR <- function(the.model, config){
  lm.out <- Alteryx.ReportLM(the.model)
  lm.out <- rbind(c("Model_Name", config$`Model Name`), lm.out)
  lm.out <- rbind(lm.out, Alteryx.ReportAnova(the.model))
  lm.out
}

#' @inheritParams createReportLinearOSR
#' @export
#' @rdname createReportLinear
createReportLinearXDF <- function(the.model, config){
  AlteryxMessage2("Creation of the Analysis of Variance table was surpressed due to the use of an XDF file", iType = 2, iPriority = 3)
  lm.out <- AlteryxReportRx(the.model)
  lm.out <- rbind(c("Model_Name", config$`Model Name`), lm.out)
  lm.out
}
#' Create a data frame with elnet/cv.glmnet containing an elnet model object summary
#'
#'
#' The function createReportGLMNET creates a data frame of an elnet/cv.glmnet model's summary
#' output that can more easily be handled by Alteryx's reporting tools. The
#' function returns a data frame containing the model's coeffcients.
#'
#' @param glmnet_obj glmnet or cv.glmnet model object whose non-zero coefficients are
#'  put into a data frame
#' @author Bridget Toomey
#' @export
#' @family Alteryx.Report

createReportGLMNET <- function(glmnet_obj) {
  coefs_out <- coef(glmnet_obj, s = glmnet_obj$lambda_pred, exact = FALSE)
  #Coerce this result to a vector so we can put it in a data.frame
  #along with the variable names.
  vector_coefs_out <- as.vector(coefs_out)
  return(data.frame(Coefficients = rownames(coefs_out), Values = vector_coefs_out))
}

#' Create Plots
#'
#' Prepare the basic regression diagnostic plots if it is requested
#' and their isn't the combination of singularities and the use of
#' sampling weights.
#'
#' @param the.model model object
#' @export
createPlotOutputsLinearOSR <- function(the.model){
  par(mfrow=c(2, 2), mar=c(5, 4, 2, 2) + 0.1)
  plot(the.model)
}

#' Plots in XDF
#'
#' @export
createPlotOutputsLinearXDF <- function(){
  noDiagnosticPlot("The diagnostic plot is not available for XDF based models")
}


