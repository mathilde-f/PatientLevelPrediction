# @file LearningCurve.R
#
# Copyright 2019 Observational Health Data Sciences and Informatics
#
# This file is part of PatientLevelPrediction
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' @title createLearningCurve
#'
#' @description Creates a learning curve object, which can be plotted using the
#'  \code{plotLearningCurve()} function.
#' 
#' @param population The population created using \code{createStudyPopulation()}
#'   that will be used to develop the model.
#' @param plpData An object of type \code{plpData} - the patient level
#'   prediction data extracted from the CDM.
#' @param modelSettings An object of class \code{modelSettings} created using
#'   one of the function:
#'   \itemize{
#'     \item{{setLassoLogisticRegression} - a lasso logistic regression
#'       model}
#'     \item{\code{setGradientBoostingMachine} - a gradient boosting machine}
#'     \item{\code{setRandomForest} - a random forest model}
#'     \item{\code{setKNN} - a k-nearest neighbour model}
#'   }
#' @param testSplit Specifies the type of evaluation used. Can be either 
#'   \code{'person'} or \code{'time'}. The value \code{'time'} finds the date
#'   that splots the population into the testing and training fractions
#'   provided. Patients with an index after this date are assigned to the test
#'   set and patients with an index prior to this date are assigned to the
#'   training set. The value \code{'person'} splits the data randomly into
#'   testing and training sets according to fractions provided. The split is
#'   stratified by the class label.
#' @param testFraction The fraction of the data, which will be used as the 
#'   testing set in the patient split evaluation.
#' @param trainFractions A list of training fractions to create models for.
#' @param splitSeed The seed used to split the testing and training set when
#'   using a 'person' type split                  
#' @param nfold The number of folds used in the cross validation (default = 
#'   \code{3}).
#' @param indexes A dataframe containing a rowId and index column where the 
#'   index value of -1 means in the test set, and positive integer represents
#'   the cross validation fold (default is \code{NULL}).
#' @param verbosity Sets the level of the verbosity. If the log level is at or
#'   higher in priority than the logger threshold, a message will print. The 
#'   levels are:
#'   \itemize{
#'     \item{\code{DEBUG} - highest verbosity showing all debug statements}
#'     \item{\code{TRACE} - showing information about start and end of steps}
#'     \item{\code{INFO} - show informative messages (default)}
#'     \item{\code{WARN} - show warning messages}
#'     \item{\code{ERROR} - show error messages}
#'     \item{\code{FATAL} - be silent except for fatal errors}
#'   }
#' @param clearffTemp Clears the temporary ff-directory after each iteration. 
#'   This can be useful, if the fitted models are large.
#' @param minCovariateFraction Minimum covariate prevalence in population to
#'   avoid removal during preprocssing.
#' @param normalizeData Whether to normalise the data
#' @param saveDirectory Location to save log and results
#' @param savePlpData Whether to save the plpData
#' @param savePlpResult Whether to save the plpResult
#' @param savePlpPlots Whether to save the plp plots
#' @param saveEvaluation Whether to save the plp performance csv files
#' @param timeStamp Include a timestamp in the log
#' @param analysisId The analysis unique identifier
#'
#' @return A learning curve object containing the various performance measures
#'  obtained by the model for each training set fraction. It can be plotted
#'  using \code{plotLearningCurve}.
#' 
#' @examples
#' \dontrun{
#' # define model
#' modelSettings = PatientLevelPrediction::setLassoLogisticRegression()
#' 
#' # create learning curve
#' learningCurve <- PatientLevelPrediction::createLearningCurve(population,
#'                                                              plpData,
#'                                                              modelSettings)
#' # plot learning curve
#' PatientLevelPrediction::plotLearningCurve(learningCurve)
#' }
#' 
#' @export
createLearningCurve <- function(population,
                                plpData,
                                modelSettings,
                                testSplit = 'person',
                                testFraction = 0.25,
                                trainFractions = c(0.25, 0.50, 0.75),
                                splitSeed = NULL,
                                nfold = 3,
                                indexes = NULL,
                                verbosity = 'TRACE',
                                clearffTemp = FALSE,
                                minCovariateFraction = 0.001,
                                
                                normalizeData = T,
                                saveDirectory = getwd(),
                                savePlpData = F,
                                savePlpResult = F,
                                savePlpPlots = F,
                                saveEvaluation = F,
                                timeStamp = FALSE,
                                analysisId = NULL) {
  
  if (is.null(analysisId)) {
    analysisId <- gsub(':', '', gsub('-', '', gsub(' ', '', Sys.time())))
  }
  
  # remove all registered loggers
  ParallelLogger::clearLoggers()
  
  # number of training set fractions
  nRuns <- length(trainFractions)
  
  # record global start time
  ExecutionDateTime <- Sys.time()
  
  settings = list(population = population, 
                  plpData = plpData, 
                  minCovariateFraction = minCovariateFraction,
                  normalizeData = normalizeData,
                  modelSettings = modelSettings,
                  testSplit = testSplit,
                  testFraction = testFraction,
                  splitSeed = splitSeed,
                  nfold = nfold,
                  indexes = indexes,
                  saveDirectory = saveDirectory,
                  savePlpData = savePlpData,
                  savePlpResult = savePlpResult,
                  savePlpPlots = savePlpPlots,
                  saveEvaluation = saveEvaluation,
                  verbosity = verbosity,
                  timeStamp = timeStamp)
  
  learningCurve <- lapply(1:nRuns, function(i){
                                      
    settings$trainFraction = trainFractions[i]
    settings$analysisId = paste(analysisId, '_', i)                                  
    result <- do.call(runPlp, settings)  
    
    executeTime <- result$executionSummary$TotalExecutionElapsedTime
    
    result <- as.data.frame(result$performanceEvaluation$evaluationStatistics)

    df <- data.frame( x = trainFractions[i] * 100,
                      name = c('executionTime',paste0(result$Eval, result$Metric)), 
                      value = c(as.double(executeTime) ,as.double(as.character(result$Value)))
                      )
    df$name <- as.character(df$name)
    df$name[df$name == 'trainAUC.auc'] <- 'trainAUCROC'
    df$name[df$name == 'testAUC.auc'] <- 'testAUCROC'
    df$name[df$name == 'trainpopulationSize'] <- 'popSizeTrain'
    df$name[df$name == 'trainoutcomeCount'] <- 'outcomeCountTrain'
    df$name <- gsub('\\.Gradient','',gsub('\\.Intercept', '', df$name))
    
    df <- df[-grep('auc_',df$name),]
    
    df <- reshape2::dcast(df, x~ name)
  
    # return data frame row for each run
    return(df)
  })
  
  learningCurve <- do.call(rbind,learningCurve)

  ParallelLogger::clearLoggers()
  
  names(learningCurve) <- c(
    "Fraction",
    "Time",
    "Occurrences",
    "Observations",
    "TestROC",
    "TestPR",
    "TestBrierScaled",
    "TestBrierScore",
    "TestCalibrationIntercept",
    "TestCalibrationSlope",
    "outcomeCountTest",
    "popSizeTest",
    "TrainROC",
    "TrainPR",
    "TrainBrierScaled",
    "TrainBrierScore",
    "TrainCalibrationIntercept",
    "TrainCalibrationSlope"
  )

  
  endTime <- Sys.time()
  TotalExecutionElapsedTime <-
    as.numeric(difftime(endTime, ExecutionDateTime,
                        units = "secs"))
  ParallelLogger::logInfo('Finished in ', round(TotalExecutionElapsedTime), ' secs.')
  
  return(learningCurve)
}

#' @title createLearningCurvePar
#' 
#' @description Creates a learning curve in parallel, which can be plotted using
#'  the \code{plotLearningCurve()} function. Currently this functionality is
#'  only supported by Lasso Logistic Regression.
#' 
#' @param population The population created using \code{createStudyPopulation()}
#'   that will be used to develop the model.
#' @param plpData An object of type \code{plpData} - the patient level
#'   prediction data extracted from the CDM.
#' @param modelSettings An object of class \code{modelSettings} created using
#'   one of the function. Currently only one model is supported:
#'   \itemize{
#'     \item{\code{setLassoLogisticRegression} - a lasso logistic regression
#'       model}
#'   }
#' @param testSplit Specifies the type of evaluation used. Can be either 
#'   \code{'person'} or \code{'time'}. The value \code{'time'} finds the date
#'   that splots the population into the testing and training fractions
#'   provided. Patients with an index after this date are assigned to the test
#'   set and patients with an index prior to this date are assigned to the
#'   training set. The value \code{'person'} splits the data randomly into
#'   testing and training sets according to fractions provided. The split is
#'   stratified by the class label.
#' @param testFraction The fraction of the data, which will be used as the 
#'   testing set in the patient split evaluation.
#' @param trainFractions A list of training fractions to create models for.
#' @param splitSeed The seed used to split the testing and training set when
#'   using a 'person' type split                  
#' @param nfold The number of folds used in the cross validation (default = 
#'   \code{3}).
#' @param indexes A dataframe containing a rowId and index column where the 
#'   index value of -1 means in the test set, and positive integer represents
#'   the cross validation fold (default is \code{NULL}).
#' @param verbosity Sets the level of the verbosity. If the log level is at or
#'   higher in priority than the logger threshold, a message will print. The 
#'   levels are:
#'   \itemize{
#'     \item{\code{DEBUG} - highest verbosity showing all debug statements}
#'     \item{\code{TRACE} - showing information about start and end of steps}
#'     \item{\code{INFO} - show informative messages (default)}
#'     \item{\code{WARN} - show warning messages}
#'     \item{\code{ERROR} - show error messages}
#'     \item{\code{FATAL} - be silent except for fatal errors}
#'   }
#' @param clearffTemp Clears the temporary ff-directory after each iteration. 
#'   This can be useful, if the fitted models are large.
#' @param minCovariateFraction Minimum covariate prevalence in population to
#'   avoid removal during preprocssing.
#' @param normalizeData Whether to normalise the data
#' @param saveDirectory Location to save log and results
#' @param savePlpData Whether to save the plpData
#' @param savePlpResult Whether to save the plpResult
#' @param savePlpPlots Whether to save the plp plots
#' @param saveEvaluation Whether to save the plp performance csv files
#' @param timeStamp Include a timestamp in the log
#' @param analysisId The analysis unique identifier
#' @return A learning curve object containing the various performance measures
#'  obtained by the model for each training set fraction. It can be plotted
#'  using \code{plotLearningCurve}.
#' 
#' @examples
#' \dontrun{
#' # define model
#' modelSettings = setLassoLogisticRegression()
#' 
#' # register parallel backend
#' registerParallelBackend()
#' 
#' # create learning curve
#' learningCurve <- createLearningCurvePar(population,
#'                                         plpData,
#'                                         modelSettings)
#' # plot learning curve
#' plotLearningCurve(learningCurve)
#' }
#' 
#' @export
createLearningCurvePar <- function(population,
                                   plpData,
                                   modelSettings,
                                   testSplit = 'person',
                                   testFraction = 0.25,
                                   trainFractions = c(0.25, 0.50, 0.75),
                                   splitSeed = NULL,
                                   nfold = 3,
                                   indexes = NULL,
                                   verbosity = 'TRACE',
                                   clearffTemp = FALSE,
                                   minCovariateFraction = 0.001,
                                   normalizeData = T,
                                   saveDirectory = getwd(),
                                   savePlpData = F,
                                   savePlpResult = F,
                                   savePlpPlots = F,
                                   saveEvaluation = F,
                                   timeStamp = FALSE,
                                   analysisId = NULL) {
  
  # register a parallel backend
  registerParallelBackend()
  
  # verify that a parallel backend has been registered
  setup_parallel()
  
  ParallelLogger::logInfo('Started to run in parallel, this can take a while...')
  
  # record global start time
  ExecutionDateTime <- Sys.time()
  
  # store a copy of the original population
  originalPopulation <- population
  
  learningCurve <- foreach::foreach(
    i = 1:length(trainFractions),
    .combine = rbind,
    .errorhandling = "remove",
    .packages = c("doParallel",
                  "PatientLevelPrediction")
  ) %dopar% {
    
    result <- runPlp(population = originalPopulation, 
                     plpData = plpData, 
                     minCovariateFraction = minCovariateFraction,
                     normalizeData = normalizeData,
                     modelSettings = modelSettings,
                     testSplit = testSplit,
                     testFraction = testFraction,
                     trainFraction = trainFractions[i],
                     splitSeed = splitSeed,
                     nfold = nfold,
                     indexes = indexes,
                     saveDirectory = saveDirectory,
                     savePlpData = savePlpData,
                     savePlpResult = savePlpResult,
                     savePlpPlots = savePlpPlots,
                     saveEvaluation = saveEvaluation,
                     verbosity = verbosity,
                     timeStamp = timeStamp,
                     analysisId = paste(analysisId, '_', i)
    )  
    
    executeTime <- result$executionSummary$TotalExecutionElapsedTime
    
    result <- as.data.frame(result$performanceEvaluation$evaluationStatistics)
    
    df <- data.frame( x = trainFractions[i] * 100,
                      name = c('executionTime',paste0(result$Eval, result$Metric)), 
                      value = c(as.double(executeTime) ,as.double(as.character(result$Value)))
    )
    df$name <- as.character(df$name)
    df$name[df$name == 'trainAUC.auc'] <- 'trainAUCROC'
    df$name[df$name == 'testAUC.auc'] <- 'testAUCROC'
    df$name[df$name == 'trainpopulationSize'] <- 'popSizeTrain'
    df$name[df$name == 'trainoutcomeCount'] <- 'outcomeCountTrain'
    df$name <- gsub('\\.Gradient','',gsub('\\.Intercept', '', df$name))
    
    df <- df[-grep('auc_',df$name),]
    
    df <- reshape2::dcast(df, x~ name)
    
    return(df)

  }
  names(learningCurve) <- c(
    "Fraction",
    "Time",
    "Occurrences",
    "Observations",
    "TestROC",
    "TestPR",
    "TestBrierScaled",
    "TestBrierScore",
    "TestCalibrationIntercept",
    "TestCalibrationSlope",
    "outcomeCountTest",
    "popSizeTest",
    "TrainROC",
    "TrainPR",
    "TrainBrierScaled",
    "TrainBrierScore",
    "TrainCalibrationIntercept",
    "TrainCalibrationSlope"
  )
  
  endTime <- Sys.time()
  TotalExecutionElapsedTime <-
    as.numeric(difftime(endTime, ExecutionDateTime,
                        units = "secs"))
  ParallelLogger::logInfo('Finished in ', round(TotalExecutionElapsedTime), ' secs.')
  
  # de-register the parallel backend by registering a sequential backend
  registerSequentialBackend()
  
  return(learningCurve)
}
