

## Test for infected/control/beads -- a placebo effect?
## The goal is therefore to find responses different than beads
## The null hypothesis is (H0): (infected == uninfected) || (infected == beads)
## The alt hypothesis is (HA): (infected != uninfected) && (infected != beads)
disjunct_tab <- function(contrast_fit, coef1, coef2, ...) {
    stat <- BiocGenerics::pmin(abs(contrast_fit[,coef1]), abs(contrast_fit[,coef2]))
    pval <- BiocGenerics::pmax(contrast_fit$p.val[,coef1], contrast_fit$p.val[,coef2])
}
## An F-test only does inf==uninf && inf==bead
## So the solution is to separately perform the two subtests and subset for the set of genes for which both are true.
## However, if you do that, the f-statistics are a little screwey, but there are a few ways to handle it:
## Perform the two separate tests and perform the following combination of the stat and p-value:
##    stat = min(|inf-uninf|, |inf-bead|)  (logFC)
##    ^^pval^^ = max(pval(inf-uninf), pval(inf-beads))
##    adj.pval = p.adjust(^^pval^^, method='BH')
## ReportingTools hwriter

#' all_pairwise()  Wrap up limma/DESeq2/EdgeR pairwise analyses in one call.
#'
#' @param input  a dataframe/vector or expt class containing count tables, normalization state, etc.
#' @param conditions default=NULL  a factor of conditions in the experiment
#' @param batches default=NULL  a factor of batches in the experiment
#' @param model_cond default=TRUE  include condition in the model?  This is likely always true.
#' @param model_batch default=FALSE  include batch in the model?
#' @param model_intercept default=FALSE  use an intercept model instead of cell means?
#' @param extra_contrasts default=NULL some extra contrasts to add to the list
#'  This can be pretty neat, lets say one has conditions A,B,C,D,E
#'  and wants to do (C/B)/A and (E/D)/A or (E/D)/(C/B) then use this
#'  with a string like: "c_vs_b_ctrla = (C-B)-A, e_vs_d_ctrla = (E-D)-A,
#'  de_vs_cb = (E-D)-(C-B),"
#' @param alt_model default=NULL an optional alternate model to use rather than just condition/batch
#' @param libsize default=NULL the library size of the original data to help voom()
#' @param ... The elipsis parameter is fed to write_limma() at the end.
#'
#' @return A list of limma, deseq, edger results.
#' @export
#' @examples
#' ## finished_comparison = eBayes(limma_output)
#' ## data_list = write_limma(finished_comparison, workbook="excel/limma_output.xls")
all_pairwise <- function(input, conditions=NULL, batches=NULL, model_cond=TRUE,
                         model_batch=TRUE, model_intercept=FALSE, extra_contrasts=NULL,
                         alt_model=NULL, libsize=NULL, annot_df=NULL, ...) {
    arglist <- list(...)
    conditions <- get0('conditions')
    batches <- get0('batches')
    model_cond <- get0('model_cond')
    model_batch <- get0('model_batch')
    model_intercept <- get0('model_intercept')
    extra_contrasts <- get0('model_contrasts')
    alt_model <- get0('alt_model')
    libsize <- get0('libsize')
    if (is.null(model_cond)) {
        model_cond <- TRUE
    }
    if (is.null(model_batch)) {
        model_batch <- FALSE
    }
    if (is.null(model_intercept)) {
        model_intercept <- FALSE
    }

    limma_result <- limma_pairwise(input, conditions=conditions, batches=batches,
                                   model_cond=model_cond, model_batch=model_batch,
                                   model_intercept=model_intercept, extra_contrasts=extra_contrasts,
                                   alt_model=alt_model, libsize=libsize, annot_df=annot_df, ...)
    deseq_result <- deseq2_pairwise(input, conditions=conditions, batches=batches,
                                    model_cond=model_cond, model_batch=model_batch,
                                    model_intercept=model_intercept, extra_contrasts=extra_contrasts,
                                    alt_model=alt_model, libsize=libsize, annot_df=annot_df, ...)
    edger_result <- edger_pairwise(input, conditions=conditions, batches=batches,
                                   model_cond=model_cond, model_batch=model_batch,
                                   model_intercept=model_intercept, extra_contrasts=extra_contrasts,
                                   alt_model=alt_model, libsize=libsize, annot_df=annot_df, ...)
    basic_result <- basic_pairwise(input, conditions, ...)

    result_comparison <- compare_tables(limma=limma_result, deseq=deseq_result,
                                        edger=edger_result, basic=basic_result,
                                        annot_df=annot_df, ...)
    ret <- list(limma=limma_result, deseq=deseq_result, edger=edger_result,
                basic=basic_result, comparison=result_comparison)
    return(ret)
}

#' combine_de_table()  Given a limma, edger, and deseq table, combine them
#'
#' @param li  a limma output
#' @param ed  a edger output
#' @param de  a deseq output
combine_de_table <- function(li, ed, de, table, annot_df=NULL, inverse=FALSE) {
    li <- li$all_tables[[table]]
    colnames(li) <- c("limma_logfc","limma_ave","limma_t","limma_p","limma_adjp","limma_b","limma_q")
    li <- li[,c("limma_logfc","limma_ave","limma_t","limma_b","limma_p","limma_adjp","limma_q")]
    de <- de$all_tables[[table]]
    colnames(de) <- c("deseq_basemean","deseq_logfc","deseq_lfcse","deseq_stat","deseq_p","deseq_adjp","deseq_q")
    de <- de[,c("deseq_logfc","deseq_basemean","deseq_lfcse","deseq_stat","deseq_p","deseq_adjp","deseq_q")]
    ed <- ed$all_tables[[table]]
    colnames(ed) <- c("edger_logfc","edger_logcpm","edger_lr","edger_p","edger_adjp","edger_q")
    comb <- merge(li, de, by="row.names")
    comb <- merge(comb, ed, by.x="Row.names", by.y="row.names")
    rownames(comb) <- comb$Row.names
    comb <- comb[-1]
    comb[is.na(comb)] <- 0
    if (isTRUE(inverse)) {
        comb$limma_logfc <- comb$limma_logfc * -1
        comb$deseq_logfc <- comb$deseq_logfc * -1
        comb$edger_logfc <- comb$edger_logfc * -1
    }
    temp_fc <- cbind(as.numeric(comb$limma_logfc),
                     as.numeric(comb$edger_logfc),
                     as.numeric(comb$deseq_logfc))
    temp_fc <- preprocessCore::normalize.quantiles(as.matrix(temp_fc))
    comb$fc_meta <- rowMeans(temp_fc, na.rm=TRUE)
    comb$fc_var <- genefilter::rowVars(temp_fc, na.rm=TRUE)
    comb$fc_varbymed <- comb$fc_var / comb$fc_meta
    temp_p <- cbind(as.numeric(comb$limma_p),
                    as.numeric(comb$edger_p),
                    as.numeric(comb$deseq_p))
    comb$p_meta <- rowMeans(temp_p, na.rm=TRUE)
    comb$p_var <- genefilter::rowVars(temp_p, na.rm=TRUE)
    if (!is.null(annot_df)) {
        comb <- merge(annot_df, comb, by="row.names", all.y=TRUE)
        rownames(comb) <- comb$Row.names
        comb <- comb[-1]
    }
    return(comb)
}

deprint <- function(f){
    return(function(...) { capture.output(w<-f(...)); return(w); })
}

#' combine_de_tables()  Combine portions of deseq/limma/edger table output
#'
#' This hopefully makes it easy to compare the outputs from limma/DESeq2/EdgeR on a table-by-table basis.
#'
#' @param all_pairwise_result  the output from all_pairwise()
#' @param table default='wt_vs_mut'  the name of a table comparison performed by deseq/limma/edger.
#' @param keepers default NULL  a list of reformatted table names to explicitly keep certain contrasts in specific orders
#'
#' @return a table combinine limma/edger/deseq outputs.
#' @seealso \code{\link{all_pairwise}}
#' @export
#' @examples
#' \dontrun{
#' pretty = combine_de_tables(big_result, table='t12_vs_t0')
#' }
combine_de_tables <- function(all_pairwise_result, annot_df=NULL,
                              excel=NULL, excel_title="Table SXXX: Combined Differential Expression of YYY",
                              excel_sheet="combined_DE", keepers="all", add_plots=FALSE) {
    limma <- all_pairwise_result$limma
    deseq <- all_pairwise_result$deseq
    edger <- all_pairwise_result$edger

    combo <- list()
    plots <- list()
    sheet_count <- 0
    if (class(keepers) == 'list') {
        ## Then keep specific tables in specific orientations.
        for (name in names(keepers)) {
            message(paste0("Working on ", name))
            sheet_count <- sheet_count + 1
            numerator <- keepers[[name]][[1]]
            denominator <- keepers[[name]][[2]]
            same_string <- paste0(numerator, "_vs_", denominator)
            inverse_string <- paste0(denominator, "_vs_", numerator)
            dat <- NULL
            plt <- NULL
            found <- 0
            for (tab in names(edger$contrast_list)) {
                if (tab == same_string) {
                    found <- found + 1
                    dat <- combine_de_table(limma, edger, deseq, tab, annot_df=annot_df)
                    plt <- suppressMessages(limma_coefficient_scatter(limma, x=numerator, y=denominator, gvis_filename=NULL))$scatter
                } else if (tab == inverse_string) {
                    found <- found + 1
                    dat <- combine_de_table(limma, edger, deseq, tab, annot_df=annot_df, inverse=TRUE)
                    plt <- suppressMessages(limma_coefficient_scatter(limma, x=denominator, y=numerator, gvis_filename=NULL))$scatter
                }
            }
            if (found == 0) {
                stop(paste0("Did not find either ", same_string, " nor ", inverse_string, "."))
            }
            combo[[name]] <- dat
            plots[[name]] <- plt
        }
    } else if (class(keepers) == 'character' & keepers == 'all') {
        for (tab in names(edger$contrast_list)) {
            message(paste0("Working on table: ", tab))
            sheet_count <- sheet_count + 1
            dat <- combine_de_table(limma, edger, deseq, tab, annot_df=annot_df)
            combo[[tab]] <- dat
            splitted <- strsplit(x=tab, split="_vs_")
            xname <- splitted[[1]][1]
            yname <- splitted[[1]][2]
            plots[[tab]] <- suppressMessages(hpgltools::limma_coefficient_scatter(limma, x=xname, y=yname, gvis_filename=NULL))$scatter
        }
    } else if (class(keepers) == 'character') {
        table <- keepers
        sheet_count <- sheet_count + 1
        if (table %in% names(edger$contrast_list)) {
            message(paste0("I found ", table, " in the available contrasts."))
        } else {
            message(paste0("I did not find ", table, " in the available contrasts."))
            message(paste0("The available tables are: ", names(edger$contrast_list)))
            table <- names(edger$contrast_list)[[1]]
            message(paste0("Choosing the first table: ", table))
        }
        combo[[table]] <- combine_de_table(limma, edger, deseq, table, annot_df=annot_df)
        splitted <- strsplit(x=tab, split="_vs_")
        xname <- splitted[[1]][1]
        yname <- splitted[[1]][2]
        plots[[name]] <- suppressMessages(limma_coefficient_scatter(limma, x=xname, y=yname))$scatter
    } else {
        stop("I don't know what to do with your specification of tables to keep.")
    }

    if (!is.null(excel)) {
        ## Starting a new counter of sheets.
        count <- 0
        for (tab in names(combo)) {
            count <- count + 1
            ddd <- combo[[count]]
            oddness = summary(ddd) ## until I did this I was getting errors I am guessing devtools::load_all() isn't clearing everything
            final_excel_title <- gsub(pattern='YYY', replacement=tab, x=excel_title)
            xls_result <- write_xls(data=ddd, sheet=tab, file=excel, title=final_excel_title, newsheet=TRUE)
            if (isTRUE(add_plots)) {
                plot_column <- xls_result$end_col + 2
                message(paste0("Attempting to add a coefficient plot for ", names(combo)[[count]], " at column ", plot_column))
                a_plot <- plots[[count]]
                print(a_plot)
                openxlsx::insertPlot(xls_result$workbook, tab, width=6, height=6,
                                     startCol=plot_column, startRow=2, fileType="png", units="in")
                ## Maybe this saveWorkbook() call is not needed given the one that follows shortly.
                openxlsx::saveWorkbook(xls_result$workbook, xls_result$file, overwrite=TRUE)
            }
        }  ## End for loop
        count <- count + 1
        ## Add a graph on the final sheet of how similar the result types were
        summary <- all_pairwise_result$comparison$comp
        summary_plot <- all_pairwise_result$comparison$heat
        openxlsx::addWorksheet(xls_result$workbook, sheetName="pairwise_summary")
        openxlsx::writeData(xls_result$workbook, count,
                            x="Pairwise correlation coefficients among differential expression tools.",
                            startRow=1, startCol=1)
        hs1 <- openxlsx::createStyle(fontColour="#000000", halign="LEFT",
                                     textDecoration="bold", border="Bottom", fontSize="30")
        openxlsx::addStyle(xls_result$workbook, count, hs1, 1, 1)
        openxlsx::writeDataTable(xls_result$workbook, count, x=as.data.frame(summary),
                                 tableStyle="TableStyleMedium9", startRow=2, startCol=1, rowNames=TRUE)
        openxlsx::setColWidths(xls_result$workbook, sheet=count, widths="auto", cols=2:ncol(summary))
        openxlsx::setColWidths(xls_result$workbook, sheet=count, widths=10, cols=c(1))
        new_row <- 2 + nrow(summary)
        print(summary_plot)
        openxlsx::insertPlot(xls_result$workbook, count, width=6, height=6,
                             startCol=1, startRow=new_row, fileType="png", units="in")
        openxlsx::saveWorkbook(xls_result$workbook, xls_result$file, overwrite=TRUE)
    }
    ret <- list(data=combo, plots=plots)
    return(ret)
}

#' extract_significant_genes()  Pull the highly up/down genes in combined tables
#'
#' Given the output from combine_de_tables(), extract the fun genes.
#'
#' @param combined  the output from combine_de_tables()
#' @param according_to default='limma'  one may use the deseq, edger, limma, or meta data.
#' @param fc default=1.0  a log fold change to define 'significant'
#' @param p default=0.05  a (adjusted)p-value to define 'significant'
#' @param z default=NULL  a z-score to define 'significant'
#' @param n default=NULL  a set of top/bottom-n genes
#' @param sig_table default="excel/significant_genes.xlsx"  an excel file to write
#'
#' @return a set of up-genes, down-genes, and numbers therein
#' @seealso \code{\link{combine_de_tables}}
#' @export
extract_significant_genes <- function(combined, according_to="limma", fc=1.0, p=0.05, z=NULL,
                                      n=NULL, sig_table="excel/significant_genes.xlsx") {
    if (!is.null(combined$plots)) {
        combined <- combined$data
    }
    trimmed_up <- list()
    trimmed_down <- list()
    change_counts_up <- list()
    change_counts_down <- list()
    up_titles <- list()
    down_titles <- list()
    title_append <- ""
    if (!is.null(fc)) {
        title_append <- paste0(title_append, " fc><", fc)
    }
    if (!is.null(p)) {
        title_append <- paste0(title_append, " p<", p)
    }
    if (!is.null(z)) {
        title_append <- paste0(title_append, " z><", z)
    }
    if (!is.null(n)) {
        title_append <- paste0(title_append, " top|bottom n=", n)
    }
    num_tables <- length(names(combined))
    table_count <- 0
    for (table_name in names(combined)) {
        table_count <- table_count + 1
        message(paste0("Writing excel data sheet ", table_count, "/", num_tables))
        table <- combined[[table_name]]
        fc_column <- paste0(according_to, "_logfc")
        p_column <- paste0(according_to, "_adjp")
        trimming <- hpgltools::get_sig_genes(table, fc=fc, p=p, z=z, n=n,
                                             column=fc_column, p_column=p_column)
        trimmed_up[[table_name]] <- trimming$up_genes
        change_counts_up[[table_name]] <- nrow(trimmed_up[[table_name]])
        trimmed_down[[table_name]] <- trimming$down_genes
        change_counts_down[[table_name]] <- nrow(trimmed_down[[table_name]])
        up_title <- paste0("Table SXXX: Genes deemed significantly up in ", table_name, " with", title_append)
        up_titles[[table_name]] <- up_title
        down_title <- paste0("Table SXXX: Genes deemed significantly down in ", table_name, " with", title_append)
        down_titles[[table_name]] <- down_title
        ##xls_result <- write_xls(data=trimmed_up[[table_name]], sheet=paste0("up_",table_name), file=sig_table,
        ##                        title=up_title, overwrite_file=TRUE, newsheet=TRUE)
        ##xls_result <- write_xls(data=trimmed_down[[table_name]], sheet=paste0("down_",table_name), file=sig_table,
        ##                        title=down_title, overwrite_file=TRUE, newsheet=TRUE)
    } ## End extracting significant genes for loop
    change_counts <- cbind(change_counts_up, change_counts_down)
    summary_title <- paste0("Counting the number of changed genes by contrast with ", title_append)
    ##xls_result <- write_xls(data=change_counts, sheet="number_changed_genes", file=sig_table,
    ##                        title=summary_title,
    ##                        overwrite_file=TRUE, newsheet=TRUE)
    ret <- list(ups=trimmed_up, downs=trimmed_down, counts=change_counts,
                up_titles=up_titles, down_titles=down_titles, counts_title=summary_title)
    if (is.null(sig_table)) {
        message("Not printing excel sheets for the significant genes.")
    } else {
        message(paste0("Printing significant genes to the file: ", sig_table))
        xlsx_ret <- print_ups_downs(ret, sig_table=sig_table)
    }
    return(ret)
}

#' print_ups_downs()  Reprint the output from extract_significant_genes()
#'
#' I found myself needing to reprint these excel sheets because I added some new information.
#' This shortcuts that process for me.
#'
#' @param upsdowns  the output from extract_significant_genes()
#' @param excel_file default='excel/significant_genes_reprint.xlsx'  The excel file to write.
#'
#' @return the return from write_xls
#' @seealso \code{\link{combine_de_tables}}
#' @export
print_ups_downs <- function(upsdowns, sig_table="excel/significant_genes.xlsx") {
    ups <- upsdowns$ups
    downs <- upsdowns$downs
    up_titles <- upsdowns$up_titles
    down_titles <- upsdowns$down_titles
    summary <- upsdowns$counts
    summary_title <- upsdowns$counts_title
    table_count <- 0
    num_tables <- length(names(ups))
    for (base_name in names(ups)) {
        table_count <- table_count + 1
        up_name <- paste0("up_", base_name)
        down_name <- paste0("down_", base_name)
        up_table <- ups[[table_count]]
        down_table <- downs[[table_count]]
        up_title <- up_titles[[table_count]]
        down_title <- down_titles[[table_count]]
        message(paste0(table_count, "/", num_tables, ": Writing excel data sheet ", up_name))
        xls_result <- write_xls(data=up_table, sheet=up_name, file=sig_table,
                                title=up_title, overwrite_file=TRUE, newsheet=TRUE)
        message(paste0(table_count, "/", num_tables, ": Writing excel data sheet ", down_name))
        xls_result <- write_xls(data=down_table, sheet=down_name, file=sig_table,
                                title=down_title, overwrite_file=TRUE, newsheet=TRUE)
    }
    message("Writing changed genes summary on last sheet.")
    xls_result <- write_xls(data=summary, sheet="number_changed_genes", file=sig_table,
                            title=summary_title,
                            overwrite_file=TRUE, newsheet=TRUE)
    return(xls_result)
}

#' compare_tables()  See how similar are results from limma/deseq/edger.
#'
#' limma, DEseq2, and EdgeR all make somewhat different assumptions
#' and choices about what makes a meaningful set of differentially
#' expressed genes.  This seeks to provide a quick and dirty metric
#' describing the degree to which they (dis)agree.
#'
#' @param limma default=NULL  limma data from limma_pairwise()
#' @param deseq default=NULL  deseq data from deseq2_pairwise()
#' @param edger default=NULL  edger data from edger_pairwise()
#'
#' @return a heatmap showing how similar they are along with some
#' correlations betwee the three players.
#' @seealso \code{\link{limma_pairwise}} \code{\link{edger_pairwise}} \code{\link{deseq2_pairwise}}
#' @export
#' @examples
#' ## l = limma_pairwise(expt)
#' ## d = deseq_pairwise(expt)
#' ## e = edger_pairwise(expt)
#' ## fun = compare_tables(limma=l, deseq=d, edger=e)
compare_tables <- function(limma=NULL, deseq=NULL, edger=NULL, basic=NULL,
                           include_basic=TRUE, annot_df=annot_df, ...) {
    arglist <- list(...)
    ## Fill each column/row of these with the correlation between tools for one contrast performed
    if (class(limma) == "list") {
        ## Then this was fed the raw output from limma_pairwise,
        ## lets assume the same is true for deseq/edger too and pull out the result tables.
        limma <- limma$all_tables
        deseq <- deseq$all_tables
        edger <- edger$all_tables
        basic <- basic$all_tables
    }
    len <- length(names(deseq))
    limma_vs_edger <- list()
    limma_vs_deseq <- list()
    limma_vs_basic <- list()
    edger_vs_deseq <- list()
    edger_vs_basic <- list()
    deseq_vs_basic <- list()
    cc <- 0
    for (comp in names(deseq)) {
        ## assume all three have the same names() -- note that limma has more than the other two though
        cc <- cc + 1
        message(paste0(cc, "/", len, ": Comparing analyses: ", comp))
        l <- data.frame(limma[[comp]])
        e <- data.frame(edger[[comp]])
        d <- data.frame(deseq[[comp]])
        b <- data.frame(basic[[comp]])
        le <- merge(l, e, by.x="row.names", by.y="row.names")
        le <- le[,c("logFC.x","logFC.y")]
        lec <- stats::cor.test(le[,1], le[,2])$estimate
        ld <- merge(l, d, by.x="row.names", by.y="row.names")
        ld <- ld[,c("logFC.x","logFC.y")]
        ldc <- stats::cor.test(ld[,1], ld[,2])$estimate
        lb <- merge(l, b, by.x="row.names", by.y="row.names")
        lb <- lb[,c("logFC.x","logFC.y")]
        lbc <- stats::cor.test(lb[,1], lb[,2])$estimate
        ed <- merge(e, d, by.x="row.names", by.y="row.names")
        ed <- ed[,c("logFC.x","logFC.y")]
        edc <- stats::cor.test(ed[,1], ed[,2])$estimate
        eb <- merge(e, b, by.x="row.names", by.y="row.names")
        eb <- eb[,c("logFC.x","logFC.y")]
        ebc <- stats::cor.test(eb[,1], eb[,2])$estimate
        db <- merge(d, b, by.x="row.names", by.y="row.names")
        db <- db[,c("logFC.x","logFC.y")]
        dbc <- stats::cor.test(db[,1], db[,2])$estimate
        limma_vs_edger[[comp]] <- lec
        limma_vs_deseq[[comp]] <- ldc
        edger_vs_deseq[[comp]] <- edc
        limma_vs_basic[[comp]] <- lbc
        edger_vs_basic[[comp]] <- ebc
        deseq_vs_basic[[comp]] <- dbc
    } ## End loop
    names(limma_vs_edger) <- names(deseq)
    names(limma_vs_deseq) <- names(deseq)
    names(edger_vs_deseq) <- names(deseq)
    names(limma_vs_basic) <- names(deseq)
    names(edger_vs_basic) <- names(deseq)
    names(deseq_vs_basic) <- names(deseq)

    comparison_df <- rbind(as.numeric(limma_vs_edger), as.numeric(limma_vs_deseq))
    comparison_df <- rbind(comparison_df, as.numeric(edger_vs_deseq))
    if (isTRUE(include_basic)) {
        comparison_df <- rbind(comparison_df, as.numeric(limma_vs_basic))
        comparison_df <- rbind(comparison_df, as.numeric(edger_vs_basic))
        comparison_df <- rbind(comparison_df, as.numeric(deseq_vs_basic))
        rownames(comparison_df) <- c("le", "ld", "ed", "lb", "eb", "db")
    } else {
        rownames(comparison_df) <- c("le", "ld", "ed")
    }
    comparison_df <- as.matrix(comparison_df)
    colnames(comparison_df) <- names(deseq)
    heat_colors <- grDevices::colorRampPalette(c("white","black"))
    comparison_heatmap <- try(heatmap.3(comparison_df, scale="none", trace="none",
                                        linewidth=0.5, keysize=2, margins=c(8,8),
                                        col=heat_colors, dendrogram="none", Rowv=FALSE,
                                        Colv=FALSE, main="Compare DE tools"), silent=TRUE)
    heat <- NULL
    if (class(comparison_heatmap) != 'try-error') {
        heat <- recordPlot()
    }
    ret <- list(limma_vs_edger=limma_vs_edger, limma_vs_deseq=limma_vs_deseq,
                limma_vs_basic=limma_vs_basic, edger_vs_deseq=edger_vs_deseq,
                edger_vs_basic=edger_vs_basic, deseq_vs_basic=deseq_vs_basic,
                comp=comparison_df, heat=heat)
    return(ret)
}

#' make_exampledata()  A small hack of limma's exampleData()
#' function to allow for arbitrary data set sizes.
#'
#' @param ngenes default=1000  how many genes in the fictional data set.
#' @param columns default=5  how many samples in this data set.
#'
#' @return a matrix of pretend counts
#' @seealso \code{\link{makeExampleData}}
#' @export
#' @examples
#' ## pretend = make_exampledata()
make_exampledata <- function (ngenes=1000, columns=5) {
    q0 <- stats::rexp(ngenes, rate = 1/250)
    is_DE <- stats::runif(ngenes) < 0.3
    lfc <- stats::rnorm(ngenes, sd = 2)
    q0A <- ifelse(is_DE, q0 * 2^(lfc / 2), q0)
    q0B <- ifelse(is_DE, q0 * 2^(-lfc / 2), q0)
    ##    true_sf <- c(1, 1.3, 0.7, 0.9, 1.6)
    true_sf <- abs(stats::rnorm(columns, mean=1, sd=0.4))
    cond_types <- ceiling(sqrt(columns))
    ##    conds <- c("A", "A", "B", "B", "B")
    ##x <- sample( LETTERS[1:4], 10000, replace=TRUE, prob=c(0.1, 0.2, 0.65, 0.05) )
    conds <- sample(LETTERS[1:cond_types], columns, replace=TRUE)
    m <- t(sapply(seq_len(ngenes), function(i) sapply(1:columns, function(j) rnbinom(1,
                                                                                     mu = true_sf[j] * ifelse(conds[j] == "A", q0A[i], q0B[i]),
                                                                                     size = 1/0.2))))
    rownames(m) <- paste("gene", seq_len(ngenes), ifelse(is_DE, "T", "F"), sep = "_")
    example <- DESeq::newCountDataSet(m, conds)
    return(example)
}

#' make_pairwise_contrasts()  Run makeContrasts() with all pairwise comparisons.
#'
#' @param model  a model describing the conditions/batches/etc in the experiment
#' @param conditions  a factor of conditions in the experiment
#' @param do_identities default=TRUE  whether or not to include all the identity strings.
#' Limma can handle this, edgeR cannot.
#' @param do_pairwise default=TRUE  whether or not to include all the pairwise strings.
#' This shouldn't need to be set to FALSE, but just in case.
#' @param extra_contrasts default=NULL  an optional string of extra contrasts to include.
#'
#' @return A list including the following information:
#'   all_pairwise_contrasts = the result from makeContrasts(...)
#'   identities = the string identifying each condition alone
#'   all_pairwise = the string identifying each pairwise comparison alone
#'   contrast_string = the string passed to R to call makeContrasts(...)
#'   names = the names given to the identities/contrasts
#'
#' @seealso \code{\link{makeContrasts}}
#' @export
#' @examples
#' ## pretend = make_pairwise_contrasts(model, conditions)
make_pairwise_contrasts <- function(model, conditions, do_identities=TRUE,
                                    do_pairwise=TRUE, extra_contrasts=NULL) {
    tmpnames <- colnames(model)
    tmpnames <- gsub("data[[:punct:]]", "", tmpnames)
    tmpnames <- gsub("-", "", tmpnames)
    tmpnames <- gsub("+", "", tmpnames)
    tmpnames <- gsub("conditions", "", tmpnames)
    colnames(model) <- tmpnames
    condition_table <- table(conditions)
    identities <- list()
    contrast_string <- ""
    eval_strings <- list()
    for (c in 1:length(condition_table)) {
        identity_name <- names(condition_table[c])
        identity_string <- paste(identity_name, " = ", identity_name, ",", sep="")
        identities[identity_name] <- identity_string
        message(paste("As a reference, the identity is: ", identity_string, sep=""))
    }
    ## If I also create a sample condition 'alice', and also perform a subtraction
    ## of 'alice' from 'bob', then the full makeContrasts() will be:
    ## makeContrasts(bob=bob, alice=alice, bob_vs_alice=(bob)-(alice), levels=design)
    ## The parentheses in this case are superfluous, but they remind me that I am finally
    ## doing some match, and also they remind me that we can do much more complex things like:
    ## ((bob-alice)-(jane-alice)) or whatever....
    all_pairwise <- list()
    identity_names <- names(identities)
    lenminus <- length(identities) - 1
    for (c in 1:lenminus) {
        c_name <- names(identities[c])
        nextc <- c+1
        for (d in nextc:length(identities)) {
            d_name <- names(identities[d])
            minus_string <- paste(d_name, "_vs_", c_name, sep="")
            exprs_string <- paste(minus_string, "=", d_name, "-", c_name, ",", sep="")
            all_pairwise[minus_string] <- exprs_string
        }
    }
    ## At this point, I have strings which represent the definition of every
    ## sample condition as well as strings which represent every possible
    ## B-A where B comes somewhere after A in the model matrix.
    ## The goal now is to create the variables in the R environment
    ## and add them to makeContrasts()
    if (isTRUE(do_identities)) {
        eval_strings <- append(eval_strings, identities)
    }
    if (isTRUE(do_pairwise)) {
        eval_strings <- append(eval_strings, all_pairwise)
    }
    eval_names <- names(eval_strings)
    if (!is.null(extra_contrasts)) {
        extra_eval_strings <- strsplit(extra_contrasts, "\\n")
        extra_eval_names <- extra_eval_strings
        extra_eval_names <- stringi::stri_replace_all_regex(extra_eval_strings[[1]], "^(\\s*)(\\w+)=.*$", "$2")
        eval_strings <- append(eval_strings, extra_contrasts)
    }
##    for (f in 1:length(eval_strings)) {
##        eval_name = names(eval_strings[f])
##        print(paste("Setting ", eval_name, " with expression:<<", eval_strings[f], ">>", sep=""))
##        eval(parse(text=as.character(eval_strings[f])))
##    }
    ## Now we have bob=(somestuff) in memory in R's environment
    ## Add them to makeContrasts()
    contrast_string <- paste("all_pairwise_contrasts = limma::makeContrasts(")
    for (f in 1:length(eval_strings)) {
        ## eval_name = names(eval_strings[f])
        eval_string <- paste(eval_strings[f], sep="")
        contrast_string <- paste(contrast_string, eval_string, sep="   ")
    }
    ## The final element of makeContrasts() is the design from voom()
    contrast_string <- paste(contrast_string, "levels=model)")
    eval(parse(text=contrast_string))
    ## I like to change the column names of the contrasts because by default
    ## they are kind of obnoxious and too long to type

    if (!is.null(extra_contrasts)) {
        eval_names <- append(eval_names, extra_eval_names)
    }
    colnames(all_pairwise_contrasts) <- eval_names
    result <- list(
        all_pairwise_contrasts=all_pairwise_contrasts,
        identities=identities,
        identity_names=identity_names,
        all_pairwise=all_pairwise,
        contrast_string=contrast_string,
        names=eval_names)
    return(result)
}

#' get_sig_genes()  Get a set of up/down genes using the top/bottom n or >/< z scores away from the median.
#'
#' @param table  a table from limma/edger/deseq.
#' @param n default=NULL  a rank-order top/bottom number of genes to take.
#' @param z default=NULL  a number of z-scores >/< the median to take.
#' @param fc default=NULL  a number of fold-changes to take
#' @param p default=NULL  a p-value cutoff
#' @param fold default='plusminus'  an identifier reminding how to get the bottom portion of a fold-change (plusminus says to get the negative of the positive, otherwise 1/positive is taken).
#' @param column default='logFC'  a column to use to distinguish top/bottom
#' @param p_column default='adj.P.Val'  a column containing (adjusted or not)p-values
#'
#' @return a list of up/down genes
#' @export
get_sig_genes <- function(table, n=NULL, z=NULL, fc=NULL, p=NULL,
                          column='logFC', fold='plusminus', p_column='adj.P.Val') {
    if (is.null(z) & is.null(n) & is.null(fc)) {
        message("No n, z, nor fc provided, setting z to 1.")
        z <- 1
    }
    up_genes <- table
    down_genes <- table

    if (!is.null(p)) {
        up_idx <- up_genes[, p_column] <= p
        up_genes <- up_genes[up_idx, ]
        down_idx <- down_genes[, p_column] <= p
        down_genes <- down_genes[down_idx, ]
        ## Going to add logic in case one does not ask for fold change
        ## In that case, a p-value assertion should still know the difference between up and down
        ## But it should also still know the difference between ratio and log changes
        if (fold == 'plusminus' | fold == 'log') {
            message(paste0("Assuming the fold changes are on the log scale and so taking >< 0"))
            up_idx <- up_genes[, column] > 0.0
            up_genes <- up_genes[up_idx, ]
            down_idx <- down_genes[, column] < 0.0
            down_genes <- down_genes[down_idx, ]
        } else {
            ## plusminus refers to a positive/negative number of logfold changes from a logFC(1) = 0
            up_idx <- up_genes[, column] > 1.0
            up_genes <- up_genes[up_idx, ]
            down_idx <- down_genes[, column] < 1.0
            down_genes <- down_genes[down_idx, ]
        }
        message(paste0("After (adj)p filter, the up genes table has ", dim(up_genes)[1], " genes."))
        message(paste0("After (adj)p filter, the down genes table has ", dim(down_genes)[1], " genes."))
    }

    if (!is.null(fc)) {
        up_idx <- up_genes[, column] >= fc
        up_genes <- up_genes[up_idx, ]
        if (fold == 'plusminus' | fold == 'log') {
            message(paste0("Assuming the fold changes are on the log scale and so taking -1 * fc"))
            ## plusminus refers to a positive/negative number of logfold changes from a logFC(1) = 0
            down_idx <- down_genes[, column] <= (fc * -1)
            down_genes <- down_genes[down_idx, ]
        } else {
            message(paste0("Assuming the fold changes are on a ratio scale and so taking 1/fc"))
            ## If it isn't log fold change, then values go from 0..x where 1 is unchanged
            down_idx <- down_genes[, column] <= (1 / fc)
            down_genes <- down_genes[down_idx, ]
        }
        message(paste0("After fold change filter, the up genes table has ", dim(up_genes)[1], " genes."))
        message(paste0("After fold change filter, the down genes table has ", dim(down_genes)[1], " genes."))
    }

    if (!is.null(z)) {
        ## Take an arbitrary number which are >= and <= a value which is z zscores from the median.
        message(paste0("Getting the genes >= ", z, " z scores away from the median of all."))
        ## Use the entire table for the summary
        out_summary <- summary(table[,column])
        out_mad <- stats::mad(table[,column], na.rm=TRUE)
        up_median_dist <- out_summary["Median"] + (out_mad * z)
        down_median_dist <- out_summary["Median"] - (out_mad * z)
        ## But use the (potentially already trimmed) up/down tables for indexing
        up_idx <- up_genes[, column] >= up_median_dist
        up_genes <- up_genes[up_idx, ]
        down_idx <- down_genes[, column] <= down_median_dist
        down_genes <- down_genes[down_idx, ]
        message(paste0("After z filter, the up genes table has ", dim(up_genes)[1], " genes."))
        message(paste0("After z filter, the down genes table has ", dim(down_genes)[1], " genes."))
    }

    if (!is.null(n)) {
        ## Take a specific number of genes at the top/bottom of the rank ordered list.
        message(paste0("Getting the top and bottom ", n, " genes."))
        upranked <- up_genes[order(up_genes[, column], decreasing=TRUE), ]
        up_genes <- head(upranked, n=n)
        downranked <- down_genes[order(down_genes[, column]), ]
        down_genes <- head(downranked, n=n)
        message(paste0("After top-n filter, the up genes table has ", dim(up_genes)[1], " genes."))
        message(paste0("After bottom-n filter, the down genes table has ", dim(down_genes)[1], " genes."))
    }
    up_genes <- up_genes[order(up_genes[, column], decreasing=TRUE), ]
    down_genes <- down_genes[order(down_genes[, column], decreasing=FALSE), ]
    ret = list(up_genes=up_genes, down_genes=down_genes)
    return(ret)
}

## EOF