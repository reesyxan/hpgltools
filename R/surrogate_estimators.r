## Time-stamp: <Thu Apr 14 01:00:33 2016 Ashton Trey Belew (abelew@gmail.com)>

## Going to try and recapitulate the analyses found at:
## https://github.com/jtleek/svaseq/blob/master/recount.Rmd
## and use the results to attempt to more completely understand batch effects in our data

#' Extract some surrogate estimations from a raw data set using sva, ruv, and/or pca.
#'
#' This applies the methodologies very nicely explained by Jeff Leek at
#' https://github.com/jtleek/svaseq/blob/master/recount.Rmd
#' and attempts to use them to acquire estimates which may be applied to an experimental model
#' by either EdgeR, DESeq2, or limma.  In addition, it modifies the count tables using these
#' estimates so that one may play with the modified counts and view the changes (with PCA or heatmaps
#' or whatever).  Finally, it prints a couple of the plots shown by Leek in his document.
#' In other words, this is entirely derivative of someone much smarter than me.
#'
#' @param raw_expt a raw experiment object
#' @param estimate_type one of sva_supervised, sva_unsupervised, ruv_empirical, ruv_supervised, ruv_residuals, or pca
#' @param ... parameters fed to arglist
#' @return a list including the adjustments for a model matrix, a modified count table, and 3 plots of the known batch, surrogates, and batch/surrogate.
#' @export
get_model_adjust <- function(expt, estimate_type="sva_supervised", surrogates="be", ...) {
    arglist <- list(...)
    ## Gather all the likely pieces we can use
    design <- expt[["design"]]
    data <- as.data.frame(Biobase::exprs(expt$expressionset))
    mtrx <- as.matrix(data)
    l2_data <- NULL

    ## control type is to help empirical.controls
    control_type <- "norm"
    if (expt$transform == "raw") {
        l2_data <- transform_counts(count_table=data, transform="log2")[["count_table"]]
        control_type <- "counts"
    } else {
        l2_data <- data
    }
    conditions <- as.factor(design[["condition"]])
    batches <- as.factor(design[["batch"]])
    conditional_model <- model.matrix(~ conditions, data=data)
    null_model <- conditional_model[, 1]
    chosen_surrogates <- 1
    if (is.null(surrogates)) {
        message("No estimate nor method to find surrogates was provided. Assuming you want 1 surrogate variable.")
    } else {
        if (class(surrogates) == "character") {
            if (surrogates != "be" & surrogates != "leek") {
                message("A string was provided, but it was neither 'be' nor 'leek', assuming 'be'.")
                chosen_surrogates <- sva::num.sv(dat=mtrx, mod=conditional_model)
            } else {
                chosen_surrogates <- sva::num.sv(dat=mtrx, mod=conditional_model, method=surrogates)
            }
            message(paste0("The ", surrogates, " method chose ", chosen_surrogates, " surrogate variable(s)."))
        } else if (class(surrogates) == "numeric") {
            message(paste0("A specific number of surrogate variables was chosen: ", surrogates, "."))
            chosen_surrogates = surrogates
        }
    }

    modified_mtrx <- mtrx + 0.5
    ## Despite setting control_type to 'counts', it still gives stupid errors sometimes
    control_likelihoods <- try(sva::empirical.controls(dat=modified_mtrx, mod=conditional_model, mod0=null_model, n.sv=chosen_surrogates, type=control_type))
    if (class(control_likelihoods) == "try-error") {
        control_likelihoods = 0
    }
    if (sum(control_likelihoods) == 0) {
        if (estimate_type == "sva_supervised") {
            message("Unable to perform supervised estimations, changing to unsupervised_sva.")
            estimate_type <- "sva_supervised"
        } else if (estimate_type == "ruv_supervised") {
            message("Unable to perform supervised estimations, changing to empirical_ruv.")
            estimate_type <- "ruv_empirical"
        }
    }

    model_adjust <- NULL
    adjusted_counts <- NULL
    type_color <- NULL
    returned_counts <- NULL
    if (estimate_type == "sva_supervised") {
        message("Attempting sva supervised surrogate estimation.")
        type_color <- "red"
        supervised_sva <- sva::svaseq(mtrx, conditional_model, null_model, controls=control_likelihoods, n.sv=chosen_surrogates)
        model_adjust <- as.matrix(supervised_sva$sv)
        ## If only 1 surrogate is requested, this turns into a numeric list
    } else if (estimate_type == "svaseq") {
        found_surrogates <- sva::num.sv(mtrx, conditional_model)
        message("This ignores the surrogates parameter and uses the be method to estimate surrogates.")
        type_color <- "dodgerblue"
        if (min(rowSums(mtrx)) == 0) {
            svaseq_result <- sva::svaseq(modified_mtrx, conditional_model, null_model, n.sv=found_surrogates)
        } else {
            svaseq_result <- sva::svaseq(mtrx, conditional_model, null_model, n.sv=found_surrogates)
        }
        model_adjust <- as.matrix(svaseq_result$sv)
    } else if (estimate_type == "sva_unsupervised") {
        message("Attempting sva unsupervised surrogate estimation.")
        type_color <- "blue"
        if (min(rowSums(mtrx)) == 0) {
            unsupervised_sva_batch <- sva::svaseq(modified_mtrx, conditional_model, null_model, n.sv=chosen_surrogates)
        } else {
            unsupervised_sva_batch <- sva::svaseq(mtrx, conditional_model, null_model, n.sv=chosen_surrogates)
        }
        model_adjust <- as.matrix(unsupervised_sva_batch$sv)
    } else if (estimate_type == "pca") {
        message("Attempting pca surrogate estimation.")
        type_color <- "green"
        data_vs_means <- as.matrix(l2_data - rowMeans(l2_data))
        svd_result <- corpcor::fast.svd(data_vs_means)
        model_adjust <- as.matrix(svd_result$v[, 1:chosen_surrogates])
    } else if (estimate_type == "ruv_supervised") {
        message("Attempting ruvseq supervised surrogate estimation.")
        type_color <- "black"
        surrogate_estimate <- sva::num.sv(dat=mtrx, mod=conditional_model)
        if (min(rowSums(mtrx)) == 0) {
            control_likelihoods <- sva::empirical.controls(dat=modified_mtrx, mod=conditional_model, mod0=null_model, n.sv=surrogate_estimate)
        } else {
            control_likelihoods <- sva::empirical.controls(dat=mtrx, mod=conditional_model, mod0=null_model, n.sv=surrogate_estimate)
        }
        ruv_result <- RUVSeq::RUVg(mtrx, cIdx=as.logical(control_likelihoods), k=chosen_surrogates)
        returned_counts <- ruv_result$normalizedCounts
        model_adjust <- as.matrix(ruv_result$W)
    } else if (estimate_type == "ruv_residuals") {
        message("Attempting ruvseq residual surrogate estimation.")
        type_color <- "purple"
        ## Use RUVSeq and residuals
        ruv_input <- edgeR::DGEList(counts=data, group=conditions)
        ruv_input_norm <- edgeR::calcNormFactors(ruv_input, method="upperquartile")
        ruv_input_glm <- edgeR::estimateGLMCommonDisp(ruv_input_norm, conditional_model)
        ruv_input_tag <- edgeR::estimateGLMTagwiseDisp(ruv_input_glm, conditional_model)
        ruv_fit <- edgeR::glmFit(ruv_input_tag, conditional_model)
        ruv_res <- residuals(ruv_fit, type="deviance")
        ruv_normalized <- EDASeq::betweenLaneNormalization(mtrx, which="upper")  ## This also gets mad if you pass it a df and not matrix
        controls <- rep(TRUE, dim(data)[1])
        ruv_result <- RUVSeq::RUVr(ruv_normalized, controls, k=chosen_surrogates, ruv_res)
        model_adjust <- as.matrix(ruv_result$W)
    } else if (estimate_type == "ruv_empirical") {
        message("Attempting ruvseq empirical surrogate estimation.")
        type_color <- "orange"
        ruv_input <- edgeR::DGEList(counts=data, group=conditions)
        ruv_input_norm <- edgeR::calcNormFactors(ruv_input, method="upperquartile")
        ruv_input_glm <- edgeR::estimateGLMCommonDisp(ruv_input_norm, conditional_model)
        ruv_input_tag <- edgeR::estimateGLMTagwiseDisp(ruv_input_glm, conditional_model)
        ruv_fit <- edgeR::glmFit(ruv_input_tag, conditional_model)
        ## Use RUVSeq with empirical controls
        ## The previous instance of ruv_input should work here, and the ruv_input_norm
        ## Ditto for _glm and _tag, and indeed ruv_fit
        ## Thus repeat the first 7 lines of the previous RUVSeq before anything changes.
        ruv_lrt <- edgeR::glmLRT(ruv_fit, coef=2)
        ruv_control_table <- ruv_lrt$table
        ranked <- as.numeric(rank(ruv_control_table[["LR"]]))
        bottom_third <- (summary(ranked)[[2]] + summary(ranked)[[3]]) / 2
        ruv_controls <- ranked <= bottom_third  ## what is going on here?!
        ## ruv_controls = rank(ruv_control_table$LR) <= 400  ## some data sets fail with 400 hard-set
        ruv_result <- RUVSeq::RUVg(mtrx, ruv_controls, k=chosen_surrogates)
        model_adjust <- as.matrix(ruv_result$W)
    } else {
        type_color <- "black"
        ## If given nothing to work with, use supervised sva
        message(paste0("Did not understand ", estimate_type, ", assuming supervised sva."))
        if (min(rowSums(mtrx)) == 0) {
            supervised_sva <- sva::svaseq(mtrx, conditional_model, null_model, controls=control_likelihoods, n.sv=chosen_surrogates)
        } else {
            supervised_sva <- sva::svaseq(modified_mtrx, conditional_model, null_model, controls=control_likelihoods, n.sv=chosen_surrogates)
        }
        model_adjust <- as.matrix(supervised_sva$sv)
    }

    new_model <- cbind(conditional_model, model_adjust)
    data_modifier <- solve(t(new_model) %*% new_model) %*% t(new_model)
    transformation <- (data_modifier %*% t(mtrx))
    conds <- ncol(conditional_model)
    new_counts <- mtrx - t(as.matrix(new_model[, -c(1:conds)]) %*% transformation[-c(1:conds), ])
    ## This matches the return I get from batch_counts()
    ##if (!is.null(returned_counts)) {
    ##    ## Some methods return batch adjusted counts, do these methods agree with the above method of acquiring them?
    ##    all.equal(new_counts, returned_counts) ## no, very much no.
    ##}

    plotbatch <- as.integer(batches)
    plotcond <- as.numeric(conditions)
    x_marks <- 1:length(colnames(data))

    plot(plotbatch, type="p", pch=19, col="black", main=paste0("Known batches by sample"), xaxt="n", yaxt="n", xlab="Sample", ylab="Known batch")
    axis(1, at=x_marks, cex.axis=0.75, las=2, labels=as.character(colnames(data)))
    axis(2, at=plotbatch, cex.axis=0.75, las=2, labels=as.character(batches))
    batch_by_sample_plot <- grDevices::recordPlot()
    plot(as.numeric(model_adjust), type="p", pch=19, col=type_color,
         xaxt="n", xlab="Sample", ylab="Surrogate estimate", main=paste0("Surrogates estimated by ", estimate_type))
    axis(1, at=x_marks, cex.axis=0.75, las=2, labels=as.character(colnames(data)))
    surrogate_by_sample_plot <- grDevices::recordPlot()
    plot(model_adjust[, 1] ~ plotbatch, pch=19, col=type_color, main=paste0(estimate_type, " vs. known batches."))
    estimate_vs_sample_plot <- grDevices::recordPlot()

    ret <- list("model_adjust"=model_adjust,
                "new_counts"=new_counts,
                "batch_by_sample"=batch_by_sample_plot,
                "surrogate_by_sample"=surrogate_by_sample_plot,
                "estimate_by_sample"=estimate_vs_sample_plot)
    return(ret)
}

#' make a dotplot of some categorised factors and a set of SVs (for other factors)
#'
#' This should make a quick df of the factors and surrogates and plot them.
#' @param factors some portion of the experimental design
#' @param sv a set of surrogate variable estimations from sva/svg or batch estimates
#'
#' @examples
#' \dontrun{
#' estimate_vs_snps <- plot_svfactor(start, surrogate_estimate, "snpcategory")
#' }
plot_svfactor <- function(expt, svest, chosen_factor="snpcategory", factor_type="factor") {
    chosen <- expt[["design"]][[chosen_factor]]
    sv_df <- data.frame(
        "adjust" = svest$model_adjust[, 1],  ## Take a single estimate from compare_estimates()
        "factors" = chosen,
        "samplenames" = rownames(expt[["design"]])
    )
    samplenames <- rownames(expt[["design"]])
    my_colors <- expt[["colors"]]

    sv_melted <- reshape2::melt(sv_df, idvars="factors")
    sv_plot <- ggplot2::ggplot(sv_factor, ggplot2::aes_string(x="factors", y="value")) +
        ggplot2::geom_dotplot(binaxis="y", stackdir="center", binpositions="all", colour="black", fill=my_colors) +
        ggplot2::xlab(paste0("Experimental factor: ", chosen_factor)) +
        ggplot2::ylab(paste0("1st surrogate variable estimation")) +
        ggplot2::theme_bw()

    return(sv_plot)
}

#' Perform a comparison of the surrogate estimators demonstrated by Jeff Leek.
#' Once again this is entirely derivative, but seeks to provide similar estimates for one's own actual data
#' and catch corner cases not taken into account in that document (for example if the estimators
#' don't converge on a surrogate variable)
#'
#' This will attempt each of the surrogate estimators described by Leek: pca, sva supervised,
#' sva unsupervised, ruv supervised, ruv residuals, ruv empirical. Upon completion it will perform
#' the same limma expression analysis and plot the ranked t statistics as well as a correlation plot
#' making use of the extracted estimators against condition/batch/whatever else.
#' Finally, it does the same ranking plot against a linear fitting Leek performed and returns the
#' whole pile of information as a list.
#'
#' @param expt an experiment containing a design and other information
#' @param extra_factors character list of extra factors which may be included in the final plot of the data
#' @return a list of toys
#' @export
compare_surrogate_estimates <- function(expt, extra_factors=NULL) {
    design <- expt[["design"]]
    pca_plots <- list()
    pca_plots$null <- hpgl_pca(expt)$plot
    pca_adjust <- get_model_adjust(expt, estimate_type="pca")
    pca_plots$pca <- hpgl_pca(pca_adjust$new_counts, design=design, plot_colors=expt$colors)$plot
    sva_supervised <- get_model_adjust(expt, estimate_type="sva_supervised")
    pca_plots$svasup <- hpgl_pca(sva_supervised$new_counts, design=design, plot_colors=expt$colors)$plot
    sva_unsupervised <- get_model_adjust(expt, estimate_type="sva_unsupervised")
    pca_plots$svaunsup <- hpgl_pca(sva_unsupervised$new_counts, design=design, plot_colors=expt$colors)$plot
    ruv_supervised <- get_model_adjust(expt, estimate_type="ruv_supervised")
    pca_plots$ruvsup <- hpgl_pca(ruv_supervised$new_counts, design=design, plot_colors=expt$colors)$plot
    ruv_residuals <- get_model_adjust(expt, estimate_type="ruv_residuals")
    pca_plots$ruvresid <- hpgl_pca(ruv_residuals$new_counts, design=design, plot_colors=expt$colors)$plot
    ruv_empirical <- get_model_adjust(expt, estimate_type="ruv_empirical")
    pca_plots$ruvemp <- hpgl_pca(ruv_empirical$new_counts, design=design, plot_colors=expt$colors)$plot

    first_svs <- data.frame("condition" = as.numeric(as.factor(expt[["conditions"]])),
                            "batch" = as.numeric(as.factor(expt[["batches"]])),
                            "pca_adjust" = pca_adjust[["model_adjust"]][, 1],
                            "sva_supervised" = sva_supervised[["model_adjust"]][, 1],
                            "sva_unsupervised" = sva_unsupervised[["model_adjust"]][, 1],
                            "ruv_supervised" = ruv_supervised[["model_adjust"]][, 1],
                            "ruv_residuals" = ruv_residuals[["model_adjust"]][,1],
                            "ruv_empirical" = ruv_empirical[["model_adjust"]][,1])
    batch_adjustments <- list(
        "condition" = as.factor(expt[["conditions"]]),
        "batch" = as.factor(expt[["batches"]]),
        "pca_adjust" = pca_adjust[["model_adjust"]],
        "sva_supervised" = sva_supervised[["model_adjust"]],
        "sva_unsupervised" = sva_unsupervised[["model_adjust"]],
        "ruv_supervised" = ruv_supervised[["model_adjust"]],
        "ruv_residuals" = ruv_residuals[["model_adjust"]],
        "ruv_empirical" = ruv_empirical[["model_adjust"]])
    batch_names <- c("condition","batch","pca","sva_sup","sva_unsup","ruv_sup","ruv_resid","ruv_emp")
    if (!is.null(extra_factors)) {
        for (fact in extra_factors) {
            if (!is.null(design[, fact])) {
                batch_names <- append(x=batch_names, values=fact)
                first_svs[[fact]] <- as.numeric(as.factor(design[, fact]))
                batch_adjustments[[fact]] <- as.numeric(as.factor(design[, fact]))
            }
        }
    }
    correlations <- cor(first_svs)
    par(mar=c(5,5,5,5))
    corrplot::corrplot(correlations, method="ellipse", type="lower", tl.pos="d")
    ret_plot <- grDevices::recordPlot()

    adjustments <- c("+ batch_adjustments$batch", "+ batch_adjustments$pca",
                     "+ batch_adjustments$sva_sup", "+ batch_adjustments$sva_unsup",
                     "+ batch_adjustments$ruv_sup", "+ batch_adjustments$ruv_resid",
                     "+ batch_adjustments$ruv_emp")
    adjust_names <- c("null", "batch","pca","sva_sup","sva_unsup","ruv_sup","ruv_resid","ruv_emp")
    starter <- edgeR::DGEList(counts=Biobase::exprs(expt[["expressionset"]]))
    norm_start <- edgeR::calcNormFactors(starter)
    catplots <- vector("list", length(adjustments) + 1)  ## add 1 for a null adjustment
    names(catplots) <- adjust_names
    tstats <- list()

    ## First do a null adjust
    adjust <- ""
    counter <- 1
    num_adjust <- length(adjustments)
    message(paste0(counter, "/", num_adjust + 1, ": Performing lmFit(data) etc. with null in the model."))
    modified_formula <- as.formula(paste0("~ condition ", adjust))
    limma_design <- model.matrix(modified_formula, data=design)
    voom_result <- limma::voom(norm_start, limma_design, plot=FALSE)
    limma_fit <- limma::lmFit(voom_result, limma_design)
    modified_fit <- limma::eBayes(limma_fit)
    tstats[["null"]] <- abs(modified_fit$t[, 2])
    ##names(tstats[["null"]]) <- as.character(1:dim(data)[1])
    ## This needs to be redone to take into account how I organized the adjustments!!!
    num_adjust <- length(adjustments)
    for (adjust in adjustments) {
        counter <- counter + 1
        message(paste0(counter, "/", num_adjust, ": Performing lmFit(data) etc. with ", adjust, " in the model."))
        modified_formula <- as.formula(paste0("~ condition ", adjust))
        limma_design <- model.matrix(modified_formula, data=design)
        voom_result <- limma::voom(norm_start, limma_design, plot=FALSE)
        limma_fit <- limma::lmFit(voom_result, limma_design)
        modified_fit <- limma::eBayes(limma_fit)
        tstats[[adjust]] <- abs(modified_fit$t[, 2])
        ##names(tstats[[counter]]) <- as.character(1:dim(data)[1])
        catplots[[counter]] <- ffpe::CATplot(-rank(tstats[[adjust]]), -rank(tstats[["null"]]), maxrank=1000, make.plot=TRUE)
    }

    plot(catplots[["pca"]], ylim=c(0, 1), col="black", lwd=3, type="l", ylab="Concordance between study and different methods.", xlab="Rank")
    lines(catplots[["sva_sup"]], col="red", lwd=3, lty=2)
    lines(catplots[["sva_unsup"]], col="blue", lwd=3)
    lines(catplots[["ruv_sup"]], col="green", lwd=3, lty=3)
    lines(catplots[["ruv_resid"]], col="orange", lwd=3)
    lines(catplots[["ruv_emp"]], col="purple", lwd=3)
    legend(200, 0.5, legend=c("some stuff about methods used."), lty=c(1,2,1,3,1), lwd=3)
    catplot_together <- grDevices::recordPlot()

    ret <- list(
        "pca_adjust" = pca_adjust,
        "sva_supervised_adjust" = sva_supervised,
        "sva_unsupervised_adjust" = sva_unsupervised,
        "ruv_supervised_adjust" = ruv_supervised,
        "ruv_residual_adjust" = ruv_residuals,
        "ruv_empirical_adjust" = ruv_empirical,
        "adjustments" = batch_adjustments,
        "correlations" = correlations,
        "plot" = ret_plot,
        "pca_plots" = pca_plots,
        "catplots" = catplot_together)
    return(ret)
}

## EOF