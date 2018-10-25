#' A shortcut for replotting the percent plots from variancePartition.
#'
#' In case I wish to look at different numbers of genes from variancePartition and/or
#' different columns to sort from.
#'
#' @param varpart_output  List returned by varpart()
#' @param n  How many genes to plot.
#' @param column  The df column to use for sorting.
#' @param decreasing  high->low or vice versa?
#' @return  The percent variance bar plots from variancePartition!
#' @seealso \pkg{variancePartition}
#'  \code{\link[variancePartition]{plotPercentBars}}
#' @export
replot_varpart_percent <- function(varpart_output, n=30, column=NULL, decreasing=TRUE) {
  sorted <- varpart_output[["sorted_df"]]
  if (!is.null(column)) {
    if (column %in% colnames(sorted)) {
      sorted <- sorted[order(sorted[[column]], decreasing=decreasing), ]
    } else {
      message("The column ", column, "is not in the sorted data frame returned by varpart().")
      message("Leaving the data frame alone.")
    }
  }
  new_plot <- variancePartition::plotPercentBars(sorted[1:n, ])
  return(new_plot)
}

#' Use variancePartition to try and understand where the variance lies in a data set.
#'
#' variancePartition is the newest toy introduced by Hector.
#'
#' Tested in 19varpart.R.
#'
#' @param expt  Some data
#' @param predictor  Non-categorical predictor factor with which to begin the model.
#' @param factors  Character list of columns in the experiment design to query
#' @param chosen_factor  When checking for sane 'batches', what column to extract from the design?
#' @param do_fit  Perform a fitting using variancePartition?
#' @param cor_gene  Provide a set of genes to look at the correlations, defaults to the first gene.
#' @param cpus  Number cpus to use
#' @param genes  Number of genes to count.
#' @param parallel  use doParallel?
#' @param modify_expt  Add annotation columns with the variance/factor?
#' @return partitions  List of plots and variance data frames
#' @seealso \pkg{doParallel} \pkg{variancePartition}
#' @export
varpart <- function(expt, predictor=NULL, factors=c("condition", "batch"),
                    chosen_factor="batch", do_fit=FALSE, cor_gene=1,
                    cpus=6, genes=40, parallel=TRUE,
                    modify_expt=TRUE) {
  cl <- NULL
  para <- NULL
  ## One is not supposed to use library() in packages, but it needs to do all sorts of foolish
  ## attaching.
  tt <- sm(library("variancePartition"))
  if (isTRUE(parallel)) {
    cl <- parallel::makeCluster(cpus)
    para <- doParallel::registerDoParallel(cl)
  }
  design <- pData(expt)
  num_batches <- length(levels(as.factor(design[[chosen_factor]])))
  if (num_batches == 1) {
    message("varpart sees only 1 batch, adjusting the model accordingly.")
    factors <- factors[!grepl(pattern=chosen_factor, x=factors)]
  }
  model_string <- "~ "
  if (!is.null(predictor)) {
    model_string <- glue("{model_string}{predictor} +")
  }
  for (fact in factors) {
    model_string <- glue("{model_string} (1|{fact}) +")
  }
  model_string <- gsub(pattern="\\+$", replacement="", x=model_string)
  message("Attempting mixed linear model with: ", model_string)
  my_model <- as.formula(model_string)
  norm <- sm(normalize_expt(expt, filter=TRUE))
  data <- exprs(norm)

  message("Fitting the expressionset to the model, this is slow.")
  ##my_fit <- try(variancePartition::fitVarPartModel(data, my_model, design))
  ##message("Extracting the variances.")
  ##my_extract <- try(variancePartition::extractVarPart(my_fit))
  my_extract <- try(variancePartition::fitExtractVarPartModel(data, my_model, design))
  if (class(my_extract) == "try-error") {
    message("A couple of common errors:
An error like 'vtv downdated' may be because there are too many 0s, filter the data and rerun.
An error like 'number of levels of each grouping factor must be < number of observations' means
that the factor used is not appropriate for the analysis - it really only works for factors
which are shared among multiple samples.")
    stop()
  }
  chosen_column <- predictor
  if (is.null(predictor)) {
    chosen_column <- factors[[1]]
    message("Placing factor: ", chosen_column, " at the beginning of the model.")
  }

  my_sorted <- variancePartition:::.sortCols(my_extract)
  order_idx <- order(my_sorted[[chosen_column]], decreasing=TRUE)
  my_sorted <- my_sorted[order_idx, ]
  percent_plot <- variancePartition::plotPercentBars(my_sorted[1:genes, ])
  partition_plot <- variancePartition::plotVarPart(my_sorted)

  if (isTRUE(do_fit)) {
    message("variancePartition provides time/memory estimates for this operation.  They are lies.")
    ## Try fitting with lmer4
    fitting <- variancePartition::fitVarPartModel(exprObj=data, formula=my_model, data=design)
    idx <- order(design[["condition"]], design[["batch"]])
    first <- variancePartition::plotCorrStructure(fitting, reorder=idx)
    test_strat <- data.frame(Expression=data[3, ],
                             condition=design[["condition"]],
                             batch=design[["batch"]])
    testing <- variancePartition::plotStratify(Expression ~ batch, test_strat)
  }

  if (isTRUE(parallel)) {
    para <- parallel::stopCluster(cl)
  }

  ret <- list(
    "model_used" = my_model,
    "percent_plot" = percent_plot,
    "partition_plot" = partition_plot,
    "sorted_df" = my_sorted,
    "fitted_df" = my_extract)
  if (isTRUE(modify_expt)) {
    new_expt <- expt
    tmp_annot <- fData(new_expt)
    added_data <- my_sorted
    colnames(added_data) <- glue("variance_{colnames(added_data)}")
    tmp_annot <- merge(tmp_annot, added_data, by="row.names")
    rownames(tmp_annot) <- tmp_annot[["Row.names"]]
    tmp_annot <- tmp_annot[, -1]
    ## Make it possible to use a generic expressionset, though maybe this is
    ## impossible for this function.
    if (class(new_expt) == "ExpressionSet") {
      Biobase::fData(new_expt) <- tmp_annot
    } else {
      Biobase::fData(new_expt[["expressionset"]]) <- tmp_annot
    }
    ret[["modified_expt"]] <- new_expt
  }
  return(ret)
}

#' Attempt to use variancePartition's fitVarPartModel() function.
#'
#' Note the word 'attempt'.  This function is so ungodly slow that it probably will never be used.
#'
#' @param expt  Input expressionset.
#' @param factors  Set of factors to query
#' @param cpus  Number of cpus to use in doParallel.
#' @return  Summaries of the new model,  in theory this would be a nicely batch-corrected data set.
#' @seealso \pkg{variancePartition}
varpart_summaries <- function(expt, factors=c("condition", "batch"), cpus=6) {
  cl <- parallel::makeCluster(cpus)
  doParallel::registerDoParallel(cl)
  model_string <- "~ "
  for (fact in factors) {
    model_string <- glue("{model_string} (1|{fact}) + ")
  }
  model_string <- gsub(pattern="\\+ $", replacement="", x=model_string)
  my_model <- as.formula(model_string)
  norm <- sm(normalize_expt(expt, filter=TRUE))
  data <- exprs(norm)
  design <- expt[["design"]]
  summaries <- variancePartition::fitVarPartModel(data, my_model, design, fxn=summary)
  return(summaries)
}

## EOF
