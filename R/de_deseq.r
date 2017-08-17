#' deseq_pairwise()  Because I can't be trusted to remember '2'.
#'
#' This calls deseq2_pairwise(...) because I am determined to forget typing deseq2.
#'
#' @param ... I like cats.
#' @return stuff deseq2_pairwise results.
#' @seealso \code{\link{deseq2_pairwise}}
#' @export
deseq_pairwise <- function(...) {
    message("Hey you, use deseq2 pairwise.")
    deseq2_pairwise(...)
}

#' Set up model matrices contrasts and do pairwise comparisons of all conditions using DESeq2.
#'
#' Invoking DESeq2 is confusing, this should help.
#'
#' Tested in test_24de_deseq.R
#' Like the other _pairwise() functions, this attempts to perform all pairwise contrasts in the
#' provided data set.  The details are of course slightly different when using DESeq2.  Thus, this
#' uses the function choose_binom_dataset() to try to ensure that the incoming data is appropriate
#' for DESeq2 (if one normalized the data, it will attempt to revert to raw counts, for example).
#' It continues on to extract the conditions and batches in the data, choose an appropriate
#' experimental model, and run the DESeq analyses as described in the manual.  It defaults to using
#' an experimental batch factor, but will accept a string like 'sva' instead, in which case it will
#' use sva to estimate the surrogates, and append them to the experimental design.  The deseq_method
#' parameter may be used to apply different DESeq2 code paths as outlined in the manual.  If you
#' want to play with non-standard data, the force argument will round the data and shoe-horn it into
#' DESeq2.
#'
#' @param input  Dataframe/vector or expt class containing data, normalization state, etc.
#' @param conditions  Factor of conditions in the experiment.
#' @param batches  Factor of batches in the experiment.
#' @param model_cond  Is condition in the experimental model?
#' @param model_batch  Is batch in the experimental model?
#' @param model_intercept  Use an intercept model?  DESeq seems to not be a fan of them.
#' @param alt_model  Provide an arbitrary model here.
#' @param extra_contrasts  Provide extra contrasts here.
#' @param annot_df  Include some annotation information in the results?
#' @param force  Force deseq to accept data which likely violates its assumptions.
#' @param deseq_method  The DESeq2 manual shows a few ways to invoke it, I make 2 of them available here.
#' @param ...  Triple dots!  Options are passed to arglist.
#' @return List including the following information:
#'  run = the return from calling DESeq()
#'  denominators = list of denominators in the contrasts
#'  numerators = list of the numerators in the contrasts
#'  conditions = the list of conditions in the experiment
#'  coefficients = list of coefficients making the contrasts
#'  all_tables = list of DE tables
#' @seealso \pkg{DESeq2} \pkg{Biobase} \pkg{stats}
#' @examples
#' \dontrun{
#'  pretend = deseq2_pairwise(data, conditions, batches)
#' }
#' @export
deseq2_pairwise <- function(input=NULL, conditions=NULL,
                            batches=NULL, model_cond=TRUE,
                            model_batch=TRUE, model_intercept=FALSE,
                            alt_model=NULL, extra_contrasts=NULL,
                            annot_df=NULL, force=FALSE,
                            deseq_method="long", ...) {
    arglist <- list(...)
    if (!is.null(arglist[["input"]])) {
        input <- arglist[["input"]]
    }
    if (!is.null(arglist[["conditions"]])) {
        conditions <- arglist[["conditions"]]
    }
    if (!is.null(arglist[["batches"]])) {
        batches <- arglist[["batches"]]
    }
    if (!is.null(arglist[["model_cond"]])) {
        model_cond <- arglist[["model_cond"]]
    }
    if (!is.null(arglist[["model_batch"]])) {
        model_batch <- arglist[["model_batch"]]
    }
    if (!is.null(arglist[["model_intercept"]])) {
        model_intercept <- arglist[["model_intercept"]]
    }
    if (!is.null(arglist[["alt_model"]])) {
        alt_model <- arglist[["alt_model"]]
    }
    if (!is.null(arglist[["extra_contrasts"]])) {
        extra_contrasts <- arglist[["extra_contrasts"]]
    }
    if (!is.null(arglist[["annot_df"]])) {
        annot_df <- arglist[["annot_df"]]
    }
    if (!is.null(arglist[["force"]])) {
        force <- arglist[["force"]]
    }
    if (!is.null(arglist[["deseq_method"]])) {
        deseq_method <- arglist[["deseq_method"]]
    }
    message("Starting DESeq2 pairwise comparisons.")
    input_data <- choose_binom_dataset(input, force=force)
    ## Now that I understand pData a bit more, I should probably remove the conditions/batches slots
    ## from my expt classes.
    design <- pData(input)
    conditions <- input_data[["conditions"]]
    batches <- input_data[["batches"]]
    data <- input_data[["data"]]
    condition_table <- table(conditions)
    condition_levels <- levels(as.factor(conditions))
    ## batch_levels <- levels(as.factor(batches))
    ## Make a model matrix which will have one entry for
    ## each of the condition/batches
    summarized <- NULL
    ## Moving the size-factor estimation into this if(){} block in order to accomodate sva-ish
    ## batch estimation in the model
    deseq_sf <- NULL

    ## A caveat because this is a point of confusion
    ## choose_model() returns a few models, including intercept and non-intercept versions
    ## of the same things.  However, if model_batch is passed as something like 'sva', then
    ## it will gather surrogate estimates from sva and friends and return those estimates.
    model_choice <- choose_model(input, conditions, batches,
                                 model_batch=model_batch,
                                 model_cond=model_cond,
                                 model_intercept=model_intercept,
                                 alt_model=alt_model, ...)
    ##model_choice <- choose_model(input, conditions, batches,
    ##                             model_batch=model_batch,
    ##                             model_cond=model_cond,
    ##                             model_intercept=model_intercept,
    ##                             alt_model=alt_model, surrogates=1)
    model_including <- model_choice[["including"]]
    if (class(model_choice[["model_batch"]]) == "matrix") {
        ## The SV matrix from sva/ruv/etc are put into the model batch slot of the return from choose_model.
        ## Use them here if appropriate
        model_batch <- model_choice[["model_batch"]]
    }
    ## choose_model should now take all of the following into account
    ## Therefore the following 8 or so lines should not be needed any longer.
    model_string <- NULL
    column_data <- pData(input)
    if (isTRUE(model_batch) & isTRUE(model_cond)) {
        message("DESeq2 step 1/5: Including batch and condition in the deseq model.")
        ## summarized = DESeqDataSetFromMatrix(countData=data, colData=pData(input$expressionset), design=~ 0 + condition + batch)
        ## conditions and batch in this context is information taken from pData()
        ##model_string <- "~ batch + condition"
        model_string <- model_choice[["chosen_string"]]
        column_data[["condition"]] <- as.factor(column_data[["condition"]])
        column_data[["batch"]] <- as.factor(column_data[["batch"]])
        summarized <- DESeq2::DESeqDataSetFromMatrix(countData=data,
                                                     colData=column_data,
                                                     design=as.formula(model_string))
        dataset <- DESeq2::DESeqDataSet(se=summarized, design=as.formula(model_string))
    } else if (isTRUE(model_batch)) {
        message("DESeq2 step 1/5: Including only batch in the deseq model.")
        ##model_string <- "~ batch "
        model_string <- model_choice[["chosen_string"]]
        column_data[["batch"]] <- as.factor(column_data[["batch"]])
        summarized <- DESeq2::DESeqDataSetFromMatrix(countData=data,
                                                     colData=column_data,
                                                     design=as.formula(model_string))
        dataset <- DESeq2::DESeqDataSet(se=summarized, design=as.formula(model_string))
    } else if (class(model_batch) == "matrix") {
        message("DESeq2 step 1/5: Including a matrix of batch estimates from sva/ruv/pca in the deseq model.")
        ##model_string <- "~ condition"
        ##cond_model_string <- "~ condition"
        cond_model_string <- model_choice[["chosen_string"]]
        column_data[["condition"]] <- as.factor(column_data[["condition"]])
        summarized <- DESeq2::DESeqDataSetFromMatrix(countData=data,
                                                     colData=column_data,
                                                     design=as.formula(cond_model_string))
        dataset <- DESeq2::DESeqDataSet(se=summarized, design=as.formula(cond_model_string))
        passed <- FALSE
        num_sv <- ncol(model_batch)
        new_dataset <- deseq_try_sv(dataset, summarized, model_batch)
        dataset <- new_dataset
        rm(new_dataset)
    } else {
        message("DESeq2 step 1/5: Including only condition in the deseq model.")
        model_string <- model_choice[["chosen_string"]]
        ##model_string <- "~ condition"
        column_data[["condition"]] <- as.factor(column_data[["condition"]])
        summarized <- DESeq2::DESeqDataSetFromMatrix(countData=data,
                                                     colData=column_data,
                                                     design=as.formula(model_string))
        dataset <- DESeq2::DESeqDataSet(se=summarized, design=as.formula(model_string))
    }

    deseq_run <- NULL
    chosen_beta <- !model_intercept
    if (deseq_method == "short") {
        message("DESeq steps 2-4 in one shot.")
        deseq_run <- try(DESeq2::DESeq(dataset, fitType="parametric", betaPrior=chosen_beta), silent=TRUE)
        if (class(deseq_run) == "try-error") {
            message("A fitType of 'parametric' failed for this data, trying 'mean'.")
            deseq_run <- try(DESeq2::DESeq(dataset, fitType="mean"), silent=TRUE)
            if (class(deseq_run) == "try-error") {
                message("Both 'parametric' and 'mean' failed.  Trying 'local'.")
                deseq_run <- try(DESeq2::DESeq(dataset, fitType="local"), silent=TRUE)
                if (class(deseq_run) == "try-error") {
                    warning("All fitting types failed.  This will end badly.")
                } else {
                    message("Using a local fit seems to have worked.")
                }
            } else {
                message("Using a mean fitting seems to have worked.")
            }
        }
    } else {
        ## Eg. Using the long method of invoking DESeq.
        ## If making a model ~0 + condition -- then must set betaPrior=FALSE
        message("DESeq2 step 2/5: Estimate size factors.")
        deseq_sf <- DESeq2::estimateSizeFactors(dataset)
        message("DESeq2 step 3/5: Estimate dispersions.")
        deseq_disp <- try(DESeq2::estimateDispersions(deseq_sf, fitType="parametric"), silent=TRUE)
        if (class(deseq_disp) == "try-error") {
            message("Trying a mean fitting.")
            deseq_disp <- try(DESeq2::estimateDispersions(deseq_sf, fitType="mean"), silent=TRUE)
            if (class(deseq_disp) == "try-error") {
                warning("Both 'parametric' and 'mean' failed.  Trying 'local'.")
                deseq_disp <- try(DESeq2::estimateDispersions(deseq_sf, fitType="local"), silent=TRUE)
                if (class(deseq_disp) == "try-error") {
                    warning("All fitting types failed.  This will end badly.")
                } else {
                    message("Using a local fit seems to have worked.")
                }
            } else {
                message("Using a mean fitting seems to have worked.")
            }
        } else {
            message("Using a parametric fitting seems to have worked.")
        }
        ## deseq_run = nbinomWaldTest(deseq_disp, betaPrior=FALSE)
        message("DESeq2 step 4/5: nbinomWaldTest.")
        ## deseq_run <- DESeq2::DESeq(deseq_disp)
        deseq_run <- DESeq2::nbinomWaldTest(deseq_disp, betaPrior=chosen_beta, quiet=TRUE)
    }

    message("Plotting dispersions.")
    dispersions <- sm(try(DESeq2::plotDispEsts(deseq_run), silent=TRUE))
    dispersion_plot <- NULL
    if (class(dispersions)[[1]] != "try-error") {
        dispersion_plot <- grDevices::recordPlot()
    }

    ## possible options:  betaPrior=TRUE, betaPriorVar, modelMatrix=NULL
    ## modelMatrixType, maxit=100, useOptim=TRUE useT=FALSE df useQR=TRUE
    ## deseq_run = DESeq2::nbinomLRT(deseq_disp)
    ## Set contrast= for each pairwise comparison here!
    denominators <- list()
    numerators <- list()
    result_list <- list()
    coefficient_list <- list()
    ## The following is an attempted simplification of the contrast formulae
    number_comparisons <- sum(1:(length(condition_levels) - 1))
    inner_count <- 0
    contrasts <- c()
    for (c in 1:(length(condition_levels) - 1)) {
        denominator <- condition_levels[c]
        nextc <- c + 1
        for (d in nextc:length(condition_levels)) {
            inner_count <- inner_count + 1
            numerator <- condition_levels[d]
            comparison <- paste0(numerator, "_vs_", denominator)
            contrasts <- append(comparison, contrasts)
            message(paste0("DESeq2 step 5/5: ", inner_count, "/",
                           number_comparisons, ": Creating table: ", comparison))
            result <- as.data.frame(DESeq2::results(deseq_run,
                                                    contrast=c("condition", numerator, denominator),
                                                    format="DataFrame"))
            result <- result[order(result[["log2FoldChange"]]), ]
            colnames(result) <- c("baseMean", "logFC", "lfcSE", "stat", "P.Value", "adj.P.Val")
            ## From here on everything is the same.
            result[is.na(result[["P.Value"]]), "P.Value"] <- 1 ## Some p-values come out as NA
            result[is.na(result[["adj.P.Val"]]), "adj.P.Val"] <- 1 ## Some p-values come out as NA
            result[["baseMean"]] <- signif(x=as.numeric(result[["baseMean"]]), digits=4)
            result[["logFC"]] <- signif(x=as.numeric(result[["logFC"]]), digits=4)
            result[["lfcSE"]] <- signif(x=as.numeric(result[["lfcSE"]]), digits=4)
            result[["stat"]] <- signif(x=as.numeric(result[["stat"]]), digits=4)
            result[["P.Value"]] <- signif(x=as.numeric(result[["P.Value"]]), digits=4)
            result[["adj.P.Val"]] <- signif(x=as.numeric(result[["adj.P.Val"]]), digits=4)
            result_name <- paste0(numerator, "_vs_", denominator)
            denominators[[result_name]] <- denominator
            numerators[[result_name]] <- numerator
            if (!is.null(annot_df)) {
                result <- merge(result, annot_df, by.x="row.names", by.y="row.names")
            }
            result_list[[result_name]] <- result
        } ## End for each d
        ## Fill in the last coefficient (since the for loop above goes from 1 to n-1
        denominator <- names(condition_table[length(conditions)])
        ## denominator_name = paste0("condition", denominator)  ## maybe needed in 6 lines
    }  ## End for each c
    ## Now that we finished the contrasts, fill in the coefficient list with each set of values
    ##for (c in 1:(length(condition_levels))) {
    ##    coef <- condition_levels[c]
    ##    coef_name <- paste0("condition", coef)
    ##    test_result <- try(DESeq2::results(deseq_run,
    ##                                       contrast=as.numeric(coef_name == DESeq2::resultsNames(deseq_run))))
    ##    if (class(test_result) == "try-error") {
    ##        coefficient_list[[coef]] <- NULL
    ##    } else {
    ##        coefficient_list[[coef]] <- as.data.frame(test_result)
    ##    }
    ##}
    coefficient_df <- coef(deseq_run)
    colnames(coefficient_df) <- gsub(pattern="^condition", replacement="", x=colnames(coefficient_df))
    colnames(coefficient_df) <- gsub(pattern="^batch", replacement="", x=colnames(coefficient_df))
    colnames(coefficient_df) <- gsub(pattern="^_", replacement="", x=colnames(coefficient_df))
    remaining_list <- colnames(coefficient_df)
    ## If this is true, then intercept is the second half of the contrasts listed
    if ("Intercept" %in% remaining_list) {
        last_pair <- remaining_list[length(remaining_list)]
        intercept_pair <- strsplit(x=last_pair, split="_vs_")[[1]][2]
        newnames <- remaining_list
        newnames[[1]] <- intercept_pair
        col_number = 0
        for (newname in newnames) {
            col_number <- col_number + 1
            test_modify <- strsplit(x=newname, split="_vs_")[[1]][1]
            if (is.na(test_modify)) {
                next
            } else {
                newnames[col_number] <- test_modify
                coefficient_df[, col_number] <- coefficient_df[, col_number] - coefficient_df[, 1] 
            }
        }
        colnames(coefficient_df) <- newnames
    }

    ret_list <- list(
        "model_string" = model_string,
        "run" = deseq_run,
        "denominators" = denominators,
        "numerators" = numerators,
        "conditions" = conditions,
        "coefficients" = coefficient_df,
        "contrasts_performed" = contrasts,
        "all_tables" = result_list,
        "dispersion_plot" = dispersion_plot
    )
    return(ret_list)
}

deseq_try_sv <- function(data, summarized, svs, num_sv=NULL) {
    counts <- DESeq2::counts(data)
    passed <- FALSE
    if (is.null(num_sv)) {
        num_sv <- ncol(svs)
    }
    formula_string <- "as.formula(~ "
    for (count in 1:num_sv) {
        colname <- paste0("SV", count)
        summarized[[colname]] <- svs[, count]
        formula_string <- paste0(formula_string, " ", colname, " + ")
    }
    formula_string <- paste0(formula_string, "condition)")
    new_formula <- eval(parse(text=formula_string))
    new_summarized <- summarized
    DESeq2::design(new_summarized) <- new_formula
    data_model <- stats::model.matrix.default(DESeq2::design(summarized),
                                              data=as.data.frame(summarized@colData))
    model_columns <- ncol(data_model)
    model_rank <- qr(data_model)[["rank"]]
    if (model_rank < model_columns) {
        message(paste0("Including ", num_sv, " will fail because the resulting model is too low rank."))
        num_sv <- num_sv - 1
        message(paste0("Trying again with ", num_sv, " surrogates."))
        message("You should consider rerunning the pairwise comparison with the number of
surrogates explicitly stated with the option surrogates=number.")
        ret <- deseq_try_sv(data, summarized, svs, (num_sv - 1))
    } else {
        ## If we get here, then the number of surrogates should work with DESeq2.
        ## Perhaps I should re-calculate the variables with the specific number of variables.
        new_dataset <- DESeq2::DESeqDataSet(se=new_summarized, design=new_formula)
        return(new_dataset)
    }
}

#' Writes out the results of a deseq search using write_de_table()
#'
#' Looking to provide a single interface for writing tables from deseq and friends.
#'
#' Tested in test_24deseq.R
#'
#' @param data  Output from deseq_pairwise()
#' @param ...  Options for writing the xlsx file.
#' @seealso \pkg{DESeq2} \link{write_xls}
#' @examples
#' \dontrun{
#'  finished_comparison = deseq_pairwise(expressionset)
#'  data_list = write_deseq(finished_comparison)
#' }
#' @export
write_deseq <- function(data, ...) {
    result <- write_de_table(data, type="deseq", ...)
    return(result)
}

## EOF
