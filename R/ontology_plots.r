#' Plot the density of categories vs. the possibilities of all categories.
#'
#' This can make a large number of plots.
#'
#' @param godata Result from topgo.
#' @param table  Table of genes.
#' @return density plot as per topgo
#' @seealso \pkg{topGO}
#' @export
plot_topgo_densities <- function(godata, table) {
  ret <- list()
  for (id in table[["GO.ID"]]) {
    message(id)
    print(hpgl_GroupDensity(godata, id, ranks = TRUE))
    added_plot <- recordPlot()
    ret[[id]] <- added_plot
  }
  return(ret)
}

#' Make a pvalue plot from a df of IDs, scores, and p-values.
#'
#' This function seeks to make generating pretty pvalue plots as shown by
#' clusterprofiler easier.
#'
#' @param df  Some data from topgo/goseq/clusterprofiler.
#' @param ontology  Ontology to plot (MF,BP,CC).
#' @param fontsize  Fiddling with the font size may make some plots more readable.
#' @param numerator  Column used for printing a ratio of genes/category.
#' @param denominator  Column used for printing a ratio of genes/category.
#' @return Ggplot2 plot of pvalues vs. ontology.
#' @seealso \pkg{goseq} \pkg{ggplot2}
#'  \code{\link[goseq]{goseq}}
#' @export
plot_ontpval <- function(df, ontology = "MF", fontsize = 14, numerator = NULL, denominator = NULL) {
  if (nrow(df) == 0) {
    return(NULL)
  }
  y_name <- paste("Enriched ", ontology, " categories.", sep = "")
  ## This is very confusing, see the end of: http://docs.ggplot2.org/current/geom_bar.html
  ## for the implementation.
  reorder_size <- function(x) {
    attempt <- try(factor(x[["term"]], levels = x[["term"]]), silent = TRUE)
    new_fact <- NULL
    if (class(attempt)[1] == "try-error") {
      new_fact <- as.factor(x[["term"]])
    } else {
      new_fact <- attempt
    }
    return(new_fact)
  }

  if (!is.null(numerator) & !is.null(denominator)) {
    df[["score_string"]] <- glue("{df[[numerator]]} / {df[[denominator]]}")
  } else if (!is.null(numerator)) {
    df[["score_string"]] <- df[[numerator]]
  }

  ## Sometimes max(df[["score"]]) throws an error -- I think this just needs na.rm
  ## but if I am wrong, I will catch any other errors and just send it to
  ## (0, 1/4, 1/2, 3/4, 1)
  max_score <- max(df[["score"]], na.rm = TRUE)
  if (class(max_score) == "try-error") {
    max_score <- 1
  }
  break_list <- c(0, 1/4 * max_score,
                  1/2 * max_score, 3/4 * max_score,
                  max_score)
  pvalue_plot <- ggplot(df, aes_string(x = "reorder_size(df)",
                                       y = "score", fill = "pvalue")) +
    ggplot2::geom_col() +
    ggplot2::scale_y_continuous(expand = c(0, 0), breaks = break_list,
                                limits = c(0, max_score)) +
    ggplot2::scale_x_discrete(name = y_name) +
    ggplot2::scale_fill_continuous(low = "red", high = "blue") +
    ggplot2::theme(text = ggplot2::element_text(size = 10)) +
    ggplot2::coord_flip() +
    ggplot2::theme_bw(base_size = fontsize)

  if (!is.null(df[["score_string"]])) {
    pvalue_plot <- pvalue_plot +
      ggplot2::geom_text(parse = FALSE, size = 3, color = "white", hjust = 1.2,
                         ggplot2::aes_string(label = "score_string"))
  }
  return(pvalue_plot)
}

#' Make a pvalue plot from goseq data.
#'
#' With minor changes, it is possible to push the goseq results into a
#' clusterProfiler-ish pvalue plot.  This handles those changes and returns the
#' ggplot results.
#'
#' @param goterms Some data from goseq!
#' @param wrapped_width Number of characters before wrapping to help legibility.
#' @param cutoff Pvalue cutoff for the plot.
#' @param n How many groups to include?
#' @param mincat Minimum size of the category for inclusion.
#' @param level Levels of the ontology tree to use.
#' @param ... Arguments passed from simple_goseq()
#' @return Plots!
#' @seealso \pkg{goseq} \pkg{clusterProfiler}
#'  \code{\link[goseq]{goseq}} \code{\link{plot_ontpval}}
#' @export
plot_goseq_pval <- function(goterms, wrapped_width = 30, cutoff = 0.1,
                            n = 30, mincat = 5, level = NULL, ...) {
  if (!is.null(level)) {
    keepers <- data.frame()
    message("Getting all go levels.  This takes a moment.")
    mf_go <- golevel_df(ont = "MF")
    bp_go <- golevel_df(ont = "BP")
    cc_go <- golevel_df(ont = "CC")
    message("Finished getting go levels.")
    if (is.numeric(level)) {
      mf_idx <- (mf_go[["level"]] == level)
      mf_go <- mf_go[mf_idx, ]
      bp_idx <- (bp_go[["level"]] == level)
      bp_go <- bp_go[bp_idx, ]
      cc_idx <- (cc_go[["level"]] == level)
      cc_go <- cc_go[cc_idx, ]
    } else {
      ## The following supports stuff like level='level > 3 & level < 6'
      stmt <- glue("subset(mf_go, {level})")
      mf_go <- eval(parse(text = stmt))
      stmt <- glue("subset(bp_go, {level})")
      bp_go <- eval(parse(text = stmt))
      stmt <- glue("subset(cc_go, {level})")
      cc_go <- eval(parse(text = stmt))
    }
    keepers <- rbind(keepers, mf_go)
    keepers <- rbind(keepers, bp_go)
    keepers <- rbind(keepers, cc_go)
    message("Extracting the goterms in your chosen level.")
    goterms <- merge(goterms, keepers, by.x = "category", by.y = "GO")
  } ## End if a go level was provided.
  complete_idx <- complete.cases(goterms)
  goterms_complete <- goterms[complete_idx, ]
  mf_idx <- goterms_complete[["ontology"]] == "MF"
  bp_idx <- goterms_complete[["ontology"]] == "BP"
  cc_idx <- goterms_complete[["ontology"]] == "CC"
  plotting_mf <- goterms_complete[mf_idx, ]
  plotting_bp <- goterms_complete[bp_idx, ]
  plotting_cc <- goterms_complete[cc_idx, ]

  plotting_mf[["score"]] <- plotting_mf[["numDEInCat"]] / plotting_mf[["numInCat"]]
  new_order <- order(plotting_mf[["score"]], decreasing = FALSE)
  plotting_mf <- plotting_mf[new_order, ]
  plotting_mf <- plotting_mf[plotting_mf[["term"]] != "NULL", ]
  plotting_mf <- plotting_mf[plotting_mf[["over_represented_pvalue"]] <= cutoff, ]
  plotting_mf <- plotting_mf[plotting_mf[["numInCat"]] >= mincat, ]
  ##plotting_mf <- head(plotting_mf, n = n)
  ## Because of the way ggplot wants to order the bars, we need to go from the
  ## bottom up, ergo tail here. This ordering will be maintained in the plot by
  ## setting the levels of the factor in plot_ontpval, which should have a note.
  plotting_mf <- tail(plotting_mf, n = n)
  plotting_mf <- plotting_mf[, c("term", "over_represented_pvalue", "score",
                                 "numDEInCat", "numInCat")]
  plotting_mf[["term"]] <- as.character(lapply(strwrap(plotting_mf[["term"]],
                                                       wrapped_width,
                                                       simplify = FALSE), paste, collapse = "\n"))
  colnames(plotting_mf) <- c("term", "pvalue", "score", "num_de", "num_cat")
  mf_pval_plot <- plot_ontpval(plotting_mf,
                               ontology = "MF",
                               numerator = "num_de",
                               denominator = "num_cat")

  plotting_bp[["score"]] <- plotting_bp[["numDEInCat"]] / plotting_bp[["numInCat"]]
  new_order <- order(plotting_bp[["score"]], decreasing = FALSE)
  plotting_bp <- plotting_bp[new_order, ]
  plotting_bp <- plotting_bp[plotting_bp[["term"]] != "NULL", ]
  plotting_bp <- plotting_bp[plotting_bp[["over_represented_pvalue"]] <= cutoff, ]
  plotting_bp <- plotting_bp[plotting_bp[["numInCat"]] >= mincat, ]
  plotting_bp <- tail(plotting_bp, n = n)
  plotting_bp <- plotting_bp[, c("term", "over_represented_pvalue", "score",
                                 "numDEInCat", "numInCat")]
  colnames(plotting_bp) <- c("term", "pvalue", "score", "num_de", "num_cat")
  plotting_bp[["term"]] <- as.character(lapply(strwrap(plotting_bp[["term"]],
                                                       wrapped_width,
                                                       simplify = FALSE), paste, collapse = "\n"))
  bp_pval_plot <- plot_ontpval(plotting_bp,
                               ontology = "BP",
                               numerator = "num_de",
                               denominator = "num_cat")

  plotting_cc[["score"]] <- plotting_cc[["numDEInCat"]] / plotting_cc[["numInCat"]]
  new_order <- order(plotting_cc[["score"]], decreasing = FALSE)
  plotting_cc <- plotting_cc[new_order, ]
  plotting_cc <- plotting_cc[plotting_cc[["term"]] != "NULL", ]
  plotting_cc <- plotting_cc[plotting_cc[["over_represented_pvalue"]] <= cutoff, ]
  plotting_cc <- plotting_cc[plotting_cc[["numInCat"]] >= mincat, ]
  plotting_cc <- head(plotting_cc, n = n)
  plotting_cc <- plotting_cc[, c("term", "over_represented_pvalue", "score",
                                 "numDEInCat", "numInCat")]
  colnames(plotting_cc) <- c("term", "pvalue", "score", "num_de", "num_cat")
  plotting_cc[["term"]] <- as.character(lapply(strwrap(plotting_cc[["term"]],
                                                       wrapped_width,
                                                       simplify = FALSE), paste, collapse = "\n"))
  cc_pval_plot <- plot_ontpval(plotting_cc,
                               ontology = "CC",
                               numerator = "num_de",
                               denominator = "num_cat")

  pval_plots <- list(
    "mfp_plot_over" = mf_pval_plot,
    "bpp_plot_over" = bp_pval_plot,
    "ccp_plot_over" = cc_pval_plot,
    "mf_subset_over" = plotting_mf,
    "bp_subset_over" = plotting_bp,
    "cc_subset_over" = plotting_cc)
  return(pval_plots)
}

#' Make a pvalue plot from topgo data.
#'
#' The p-value plots from clusterProfiler are pretty, this sets the topgo data
#' into a format suitable for plotting in that fashion and returns the resulting
#' plots of significant ontologies.
#'
#' @param topgo Some data from topgo!
#' @param wrapped_width  Maximum width of the text names.
#' @param cutoff P-value cutoff for the plots.
#' @param n Maximum number of ontologies to include.
#' @param type Type of score to use.
#' @param ... arguments passed through presumably from simple_topgo()
#' @return List of MF/BP/CC pvalue plots.
#' @seealso \pkg{topgo} \pkg{clusterProfiler}
#' @export
plot_topgo_pval <- function(topgo, wrapped_width = 20, cutoff = 0.1,
                            n = 30, type = "fisher", ...) {
  kcols <- c("GO.ID", "Term", "Annotated", "Significant", type)
  ## mf_newdf <- topgo[["tables"]][["mf_subset"]][, kcols, type]
  mf_newdf <- topgo[["tables"]][["mf_subset"]][, kcols]
  mf_newdf[["term"]] <- as.character(lapply(strwrap(mf_newdf[["Term"]],
                                                    wrapped_width,
                                                    simplify = FALSE), paste,
                                            collapse = "\n"))
  mf_newdf[["pvalue"]] <- as.numeric(mf_newdf[[type]])
  ##mf_newdf <- subset(mf_newdf, get(type) <= cutoff)
  cutoff_idx <- mf_newdf[["pvalue"]] <= cutoff
  mf_newdf <- mf_newdf[cutoff_idx, ]
  mf_newdf <- mf_newdf[order(mf_newdf[["pvalue"]], mf_newdf[[type]]), ]
  mf_newdf <- head(mf_newdf, n = n)
  mf_newdf[["score"]] <- mf_newdf[["Significant"]] / mf_newdf[["Annotated"]]
  new_order <- order(mf_newdf[["score"]], decreasing = FALSE)
  mf_newdf <- mf_newdf[new_order, ]
  mf_pval_plot <- plot_ontpval(mf_newdf, ontology = "MF",
                               numerator = "Significant", denominator = "Annotated")

  bp_newdf <- topgo[["tables"]][["bp_subset"]][, kcols]
  bp_newdf[["term"]] <- as.character(lapply(strwrap(bp_newdf[["Term"]],
                                                    wrapped_width,
                                                    simplify = FALSE), paste,
                                            collapse = "\n"))
  bp_newdf[["pvalue"]] <- as.numeric(bp_newdf[[type]])
  ##bp_newdf <- subset(bp_newdf, get(type) < cutoff)
  cutoff_idx <- bp_newdf[["pvalue"]] <= cutoff
  bp_newdf <- bp_newdf[cutoff_idx, ]
  bp_newdf <- bp_newdf[order(bp_newdf[["pvalue"]], bp_newdf[[type]]), ]
  bp_newdf <- head(bp_newdf, n = n)
  bp_newdf[["score"]] <- bp_newdf[["Significant"]] / bp_newdf[["Annotated"]]
  new_order <- order(bp_newdf[["score"]], decreasing = FALSE)
  bp_newdf <- bp_newdf[new_order, ]
  bp_pval_plot <- plot_ontpval(bp_newdf, ontology = "MF")

  cc_newdf <- topgo[["tables"]][["cc_subset"]][, kcols]
  cc_newdf[["term"]] <- as.character(lapply(strwrap(cc_newdf[["Term"]],
                                                    wrapped_width,
                                                    simplify = FALSE), paste,
                                            collapse = "\n"))
  cc_newdf[["pvalue"]] <- as.numeric(cc_newdf[[type]])
  ##cc_newdf <- subset(cc_newdf, get(type) < cutoff)
  cutoff_idx <- cc_newdf[["pvalue"]] <= cutoff
  cc_newdf <- cc_newdf[cutoff_idx, ]
  cc_newdf <- cc_newdf[order(cc_newdf[["pvalue"]], cc_newdf[[type]]), ]
  cc_newdf <- head(cc_newdf, n = n)
  cc_newdf[["score"]] <- cc_newdf[["Significant"]] / cc_newdf[["Annotated"]]
  new_order <- order(cc_newdf[["score"]], decreasing = FALSE)
  cc_newdf <- cc_newdf[new_order, ]
  cc_pval_plot <- plot_ontpval(cc_newdf, ontology = "CC")

  pval_plots <- list(
    "mfp_plot_over" = mf_pval_plot,
    "bpp_plot_over" = bp_pval_plot,
    "ccp_plot_over" = cc_pval_plot)
  return(pval_plots)
}

#' Make a pvalue plot similar to that from clusterprofiler from gostats data.
#'
#' clusterprofiler provides beautiful plots describing significantly
#' overrepresented categories. This function attempts to expand the repetoire of
#' data available to them to include data from gostats. The pval_plot function
#' upon which this is based now has a bunch of new helpers now that I understand
#' how the ontology trees work better, this should take advantage of that, but
#' currently does not.
#'
#' @param gs_result Ontology search results.
#' @param wrapped_width Make the text large enough to read.
#' @param cutoff What is the maximum pvalue allowed?
#' @param n How many groups to include in the plot?
#' @param group_minsize Minimum group size before inclusion.
#' @return Plots!
#' @seealso \pkg{clusterProfiler}
#'  \code{\link{plot_ontpval}}
#' @export
plot_gostats_pval <- function(gs_result, wrapped_width = 20, cutoff = 0.1,
                              n = 30, group_minsize = 5) {
  ## TODO: replace the subset calls
  plot_list <- list()
  table_list <- list(
    "mf_over" = gs_result[["tables"]][["mf_over_enriched"]],
    "mf_under" = gs_result[["tables"]][["mf_under_enriched"]],
    "bp_over" = gs_result[["tables"]][["bp_over_enriched"]],
    "bp_under" = gs_result[["tables"]][["bp_under_enriched"]],
    "cc_over" = gs_result[["tables"]][["cc_over_enriched"]],
    "cc_under" = gs_result[["tables"]][["cc_under_enriched"]]
  )

  table_names <- names(table_list)
  for (name in table_names) {
    ont_overunder <- strsplit(x = name, split = "_")[[1]]
    ont <- ont_overunder[1]
    overunder <- ont_overunder[2]
    plotting <- table_list[[name]]
    pval_plot <- NULL
    if (is.null(plotting)) {
      pval_plot <- NULL
    } else {
      plotting[["score"]] <- plotting[["ExpCount"]]
      not_null <- plotting[["Term"]] != "NULL"
      plotting <- plotting[not_null, ]
      good_cutoff <- plotting[["Pvalue"]] <= cutoff
      plotting <- plotting[good_cutoff, ]
      good_size <- plotting[["Size"]] >= group_minsize
      plotting <- plotting[good_size, ]
      pval_order <- order(plotting[["score"]], decreasing = FALSE)
      plotting <- plotting[pval_order, ]
      plotting <- head(plotting, n = n)
      plotting <- plotting[, c("Term", "Pvalue", "score")]
      colnames(plotting) <- c("term", "pvalue", "score")
      plotting[["term"]] <- as.character(lapply(strwrap(plotting[["term"]],
                                                        wrapped_width,
                                                        simplify = FALSE), paste,
                                                collapse = "\n"))
    }
    if (nrow(plotting) > 0) {
      plot_name <- glue("{ont}p_plot_{overunder}")
      plot_list[[plot_name]] <- plot_ontpval(plotting, ontology = ont)
      subset_name <- glue("{ont}_subset_{overunder}")
      plot_list[[subset_name]] <- plotting
    }
  } ## End of the for loop.

  return(plot_list)
}

#' Make a pvalue plot from gprofiler data.
#'
#' The p-value plots from clusterProfiler are pretty, this sets the gprofiler
#' data into a format suitable for plotting in that fashion and returns the
#' resulting plots of significant ontologies.
#'
#' @param gp_result  Some data from gProfiler.
#' @param wrapped_width  Maximum width of the text names.
#' @param cutoff  P-value cutoff for the plots.
#' @param n  Maximum number of ontologies to include.
#' @param group_minsize  Minimum ontology group size to include.
#' @param scorer  Which column to use for scoring the data.
#' @param ...  Options I might pass from other functions are dropped into arglist.
#' @return List of MF/BP/CC pvalue plots.
#' @seealso \pkg{topgo} \pkg{clusterProfiler}
#' @export
plot_gprofiler_pval <- function(gp_result, wrapped_width = 30,
                                cutoff = 0.1, n = 30,
                                group_minsize = 5, scorer = "recall",
                                ...) {
  go_result <- gp_result[["go"]]
  kegg_result <- gp_result[["kegg"]]
  reactome_result <- gp_result[["reac"]]
  mi_result <- gp_result[["mi"]]
  tf_result <- gp_result[["tf"]]
  corum_result <- gp_result[["corum"]]
  hp_result <- gp_result[["hp"]]

  kept_columns <- c("p.value", "term.size", "query.size",
                    "overlap.size", "recall", "precision",
                    "term.id", "term.name", "relative.depth")
  old_options <- options(scipen = 4)
  mf_over <- go_result[go_result[["domain"]] == "MF", ]
  mf_over <- mf_over[, kept_columns]
  bp_over <- go_result[go_result[["domain"]] == "BP", ]
  bp_over <- bp_over[, kept_columns]
  cc_over <- go_result[go_result[["domain"]] == "CC", ]
  cc_over <- cc_over[, kept_columns]
  mf_over[["p.value"]] <- as.numeric(format(x = mf_over[["p.value"]],
                                            digits = 3, scientific = TRUE))
  bp_over[["p.value"]] <- as.numeric(format(x = bp_over[["p.value"]],
                                            digits = 3, scientific = TRUE))
  cc_over[["p.value"]] <- as.numeric(format(x = cc_over[["p.value"]],
                                            digits = 3, scientific = TRUE))

  gp_rewrite_df <- function(plotting_df) {
    ## First set the order of the table to be something most descriptive.
    ## For the moment, we want that to be the score.
    plotting_df[["score"]] <- plotting_df[[scorer]]
    new_order <- order(plotting_df[["score"]], decreasing = FALSE)
    plotting_df <- plotting_df[new_order, ]
    ## Drop anything with no term name
    kidx <- plotting_df[["term.name"]] != "NULL"
    plotting_df <- plotting_df[kidx, ]
    ## Drop anything outside of our pvalue cutoff
    kidx <- plotting_df[["p.value"]] <= cutoff
    plotting_df <- plotting_df[kidx, ]
    ## Drop anything with fewer than x genes in the group
    kidx <- plotting_df[["query.size"]] >= group_minsize
    plotting_df <- plotting_df[kidx, ]
    ## Because of the way ggplot wants to order the bars, we need to go from the bottom up,
    ## ergo tail here. This ordering will be maintained in the plot by setting the levels of
    ## the factor in plot_ontpval, which should have a note.
    plotting_df <- tail(plotting_df, n = n)
    plotting_df <- plotting_df[, c("term.name", "p.value", "score")]
    colnames(plotting_df) <- c("term", "pvalue", "score")
    plotting_df[["term"]] <- as.character(
      lapply(strwrap(plotting_df[["term"]],
                     wrapped_width, simplify = FALSE),
             paste, collapse = "\n"))
    return(plotting_df)
  }

  plotting_mf_over <- mf_over
  mf_pval_plot_over <- NULL
  if (is.null(mf_over) | nrow(mf_over) == 0) {
    plotting_mf_over <- NULL
  } else {
    plotting_mf_over <- gp_rewrite_df(plotting_mf_over)
    mf_pval_plot_over <- try(plot_ontpval(plotting_mf_over, ontology = "MF"),
                             silent = TRUE)
  }
  if (class(mf_pval_plot_over)[[1]] == "try-error") {
    mf_pval_plot_over <- NULL
  }

  plotting_bp_over <- bp_over
  bp_pval_plot_over <- NULL
  if (is.null(bp_over) | nrow(bp_over) == 0) {
    plotting_bp_over <- NULL
  } else {
    plotting_bp_over <- gp_rewrite_df(plotting_bp_over)
    bp_pval_plot_over <- try(plot_ontpval(plotting_bp_over, ontology = "BP"),
                             silent = TRUE)
  }
  if (class(bp_pval_plot_over)[[1]] == "try-error") {
    bp_pval_plot_over <- NULL
  }

  plotting_cc_over <- cc_over
  cc_pval_plot_over <- NULL
  if (is.null(cc_over) | nrow(cc_over) == 0) {
    plotting_cc_over <- NULL
  } else {
    plotting_cc_over <- gp_rewrite_df(plotting_cc_over)
    cc_pval_plot_over <- try(plot_ontpval(plotting_cc_over, ontology = "CC"),
                             silent = TRUE)
  }
  if (class(cc_pval_plot_over)[[1]] == "try-error") {
    cc_pval_plot_over <- NULL
  }

  plotting_kegg_over <- kegg_result
  kegg_pval_plot_over <- NULL
  if (is.null(kegg_result) | nrow(kegg_result) == 0) {
    plotting_kegg_over <- NULL
  } else {
    plotting_kegg_over <- gp_rewrite_df(plotting_kegg_over)
    kegg_pval_plot_over <- try(plot_ontpval(plotting_kegg_over, ontology = "KEGG"),
                               silent = TRUE)
  }
  if (class(kegg_pval_plot_over)[[1]] == "try-error") {
    kegg_pval_plot_over <- NULL
  }

  plotting_reactome_over <- reactome_result
  reactome_pval_plot_over <- NULL
  if (is.null(reactome_result) | nrow(reactome_result) == 0) {
    plotting_reactome_over <- NULL
  } else {
    plotting_reactome_over <- gp_rewrite_df(plotting_reactome_over)
    reactome_pval_plot_over <- try(plot_ontpval(plotting_reactome_over, ontology = "Reactome"),
                                   silent = TRUE)
  }
  if (class(reactome_pval_plot_over)[[1]] == "try-error") {
    reactome_pval_plot_over <- NULL
  }

  plotting_mi_over <- mi_result
  mi_pval_plot_over <- NULL
  if (is.null(mi_result) | nrow(mi_result) == 0) {
    plotting_mi_over <- NULL
  } else {
    plotting_mi_over <- gp_rewrite_df(plotting_mi_over)
    mi_pval_plot_over <- try(plot_ontpval(plotting_mi_over, ontology = "miRNA"),
                             silent = TRUE)
  }
  if (class(mi_pval_plot_over)[[1]] == "try-error") {
    mi_pval_plot_over <- NULL
  }

  plotting_tf_over <- tf_result
  tf_pval_plot_over <- NULL
  if (is.null(tf_result) | nrow(tf_result) == 0) {
    plotting_tf_over <- NULL
  } else {
    plotting_tf_over <- gp_rewrite_df(plotting_tf_over)
    tf_pval_plot_over <- try(plot_ontpval(plotting_tf_over, ontology = "Transcription factors"),
                             silent = TRUE)
  }
  if (class(tf_pval_plot_over)[[1]] == "try-error") {
    tf_pval_plot_over <- NULL
  }

  plotting_corum_over <- corum_result
  corum_pval_plot_over <- NULL
  if (is.null(corum_result) | nrow(corum_result) == 0) {
    plotting_corum_over <- NULL
  } else {
    plotting_corum_over <- gp_rewrite_df(plotting_corum_over)
    corum_pval_plot_over <- try(plot_ontpval(plotting_corum_over, ontology = "Corum"),
                                silent = TRUE)
  }
  if (class(corum_pval_plot_over)[[1]] == "try-error") {
    corum_pval_plot_over <- NULL
  }

  plotting_hp_over <- hp_result
  hp_pval_plot_over <- NULL
  if (is.null(hp_result) | nrow(hp_result) == 0) {
    plotting_hp_over <- NULL
  } else {
    plotting_hp_over <- gp_rewrite_df(plotting_hp_over)
    hp_pval_plot_over <- try(plot_ontpval(plotting_hp_over, ontology = "Human pathology"),
                             silent = TRUE)
  }
  if (class(hp_pval_plot_over)[[1]] == "try-error") {
    hp_pval_plot_over <- NULL
  }

  pval_plots <- list(
    "mfp_plot_over" = mf_pval_plot_over,
    "bpp_plot_over" = bp_pval_plot_over,
    "ccp_plot_over" = cc_pval_plot_over,
    "kegg_plot_over" = kegg_pval_plot_over,
    "reactome_plot_over" = reactome_pval_plot_over,
    "mi_plot_over" = mi_pval_plot_over,
    "tf_plot_over" = tf_pval_plot_over,
    "corum_plot_over" = corum_pval_plot_over,
    "hp_plot_over" = hp_pval_plot_over,
    "mf_subset_over" = plotting_mf_over,
    "bp_subset_over" = plotting_bp_over,
    "cc_subset_over" = plotting_cc_over,
    "kegg_subset" = plotting_kegg_over,
    "reactome_subset" = plotting_reactome_over,
    "mi_subset" = plotting_mi_over,
    "tf_subset" = plotting_tf_over,
    "corum_subset" = plotting_corum_over,
    "hp_subset" = plotting_hp_over
  )
  new_options <- options(old_options)
  return(pval_plots)
}

#' Make fun trees a la topgo from goseq data.
#'
#' This seeks to force goseq data into a format suitable for topGO and then use
#' its tree plotting function to make it possible to see significantly increased
#' ontology trees.
#'
#' @param goseq Data from goseq.
#' @param goid_map File to save go id mapping.
#' @param score_limit Score limit for the coloring.
#' @param overwrite Overwrite the trees?
#' @param selector Function for choosing genes.
#' @param pval_column Column to acquire pvalues.
#' @return A plot!
#' @seealso \pkg{Ramigo}
#' @export
goseq_trees <- function(goseq, goid_map = "id2go.map",
                        score_limit = 0.01, overwrite = FALSE,
                        selector = "topDiffGenes", pval_column = "adj.P.Val") {
  go_db <- goseq[["go_db"]]
  mapping <- make_id2gomap(goid_map = goid_map, go_db = go_db, overwrite = overwrite)
  geneID2GO <- topGO::readMappings(file = goid_map)
  annotated_genes <- names(geneID2GO)
  de_genes <- goseq[["input"]]
  if (is.null(de_genes[["ID"]])) {
    de_genes[["ID"]] <- make.names(rownames(de_genes), unique = TRUE)
  }
  interesting_genes <- factor(annotated_genes %in% de_genes[["ID"]])
  names(interesting_genes) <- annotated_genes

  if (is.null(de_genes[[pval_column]])) {
    mf_GOdata <- sm(new("topGOdata", ontology = "MF", allGenes = interesting_genes,
                        annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO))
    bp_GOdata <- sm(new("topGOdata", ontology = "BP", allGenes = interesting_genes,
                        annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO))
    cc_GOdata <- sm(new("topGOdata", ontology = "CC", allGenes = interesting_genes,
                        annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO))
  } else {
    pvals <- as.vector(as.numeric(de_genes[[pval_column]]))
    names(pvals) <- rownames(de_genes)
    tt <- try(sm(requireNamespace("topGO")), silent = TRUE)
    tt <- try(sm(attachNamespace("topGO")), silent = TRUE)
    mf_GOdata <- sm(new(
      "topGOdata", description = "MF", ontology = "MF", allGenes = pvals,
      geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO))
    bp_GOdata <- sm(new(
      "topGOdata", description = "BP", ontology = "BP", allGenes = pvals,
      geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO))
    cc_GOdata <- sm(new(
      "topGOdata", description = "CC", ontology = "CC", allGenes = pvals,
      geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO))
  }

  enriched_ids <- goseq[["all_data"]][["category"]]
  enriched_scores <- goseq[["all_data"]][["over_represented_pvalue"]]
  names(enriched_scores) <- enriched_ids

  ## Print the actual tree here for the molecular function data.
  mf_avail_nodes <- as.list(mf_GOdata@graph@nodes)
  names(mf_avail_nodes) <- mf_GOdata@graph@nodes
  mf_nodes <- enriched_scores[names(enriched_scores) %in% names(mf_avail_nodes)]
  mf_included <- length(which(mf_nodes <= score_limit))
  mf_tree_data <- try(sm(topGO::showSigOfNodes(
                                  mf_GOdata, mf_nodes, useInfo = "all",
                                  sigForAll = TRUE, firstSigNodes = mf_included,
                                  useFullNames = TRUE, plotFunction = hpgl_GOplot)),
                      silent = TRUE)
  if (class(mf_tree_data) == "try-error") {
    message("There was an error generating the MF tree.")
    mf_tree <- NULL
  } else {
    mf_tree <- recordPlot()
  }

  ## Print the biological process tree
  bp_avail_nodes <- as.list(bp_GOdata@graph@nodes)
  names(bp_avail_nodes) <- bp_GOdata@graph@nodes
  bp_nodes <- enriched_scores[names(enriched_scores) %in% names(bp_avail_nodes)]
  bp_included <- length(which(bp_nodes <= score_limit))
  bp_tree_data <- try(sm(topGO::showSigOfNodes(
                                  bp_GOdata, bp_nodes, useInfo = "all",
                                  sigForAll = TRUE, firstSigNodes = bp_included,
                                  useFullNames = TRUE, plotFunction = hpgl_GOplot)),
                      silent = TRUE)
  if (class(bp_tree_data) == "try-error") {
    message("There was an error generating the BP tree.")
    bp_tree <- NULL
  } else {
    bp_tree <- recordPlot()
  }

  ## And the cellular component tree
  cc_avail_nodes <- as.list(cc_GOdata@graph@nodes)
  names(cc_avail_nodes) <- cc_GOdata@graph@nodes
  cc_nodes <- enriched_scores[names(enriched_scores) %in% names(cc_avail_nodes)]
  cc_included <- length(which(cc_nodes <= score_limit))
  cc_tree_data <- try(sm(topGO::showSigOfNodes(
                                  cc_GOdata, cc_nodes, useInfo = "all",
                                  sigForAll = TRUE, firstSigNodes = cc_included,
                                  useFullNames = TRUE, plotFunction = hpgl_GOplot)),
                      silent = TRUE)
  if (class(cc_tree_data) == "try-error") {
    message("There was an error generating the CC tree.")
    cc_tree <- NULL
  } else {
    cc_tree <- recordPlot()
  }
  trees <- list(
    "MF_over" = mf_tree,
    "BP_over" = bp_tree,
    "CC_over" = cc_tree,
    "MF_overdata" = mf_tree_data,
    "BP_overdata" = bp_tree_data,
    "CC_overdata" = cc_tree_data)
  return(trees)
}

#' Take clusterprofile group data and print it on a tree as per topGO.
#'
#' TopGO's ontology trees can be very illustrative.  This function shoe-horns
#' clusterProfiler data into the format expected by topGO and uses it to make
#' those trees.
#'
#' @param de_genes List of genes deemed 'interesting'.
#' @param cpdata Data from simple_clusterprofiler().
#' @param goid_map Mapping file of IDs to GO ontologies.
#' @param go_db Dataframe of mappings used to build goid_map.
#' @param score_limit Scoring limit above which to ignore genes.
#' @param overwrite Overwrite an existing goid mapping file?
#' @param selector Name of a function for applying scores to the trees.
#' @param pval_column Name of the column in the GO table from which to extract scores.
#' @return plots! Trees! oh my!
#' @seealso \pkg{Ramigo}
#'  \code{\link[topGO]{showSigOfNodes}}
#' @examples
#' \dontrun{
#'  cluster_data <- simple_clusterprofiler(genes, stuff)
#'  ctrees <- cluster_trees(genes, cluster_data)
#' }
#' @export
cluster_trees <- function(de_genes, cpdata, goid_map = "id2go.map", go_db = NULL,
                          score_limit = 0.2, overwrite = FALSE, selector = "topDiffGenes",
                          pval_column = "adj.P.Val") {
  de_genes <- cpdata[["de_genes"]]
  make_id2gomap(goid_map = goid_map, go_db = go_db, overwrite = overwrite)
  geneID2GO <- topGO::readMappings(file = goid_map)
  annotated_genes <- names(geneID2GO)
  if (is.null(de_genes[["ID"]])) {
    de_genes[["ID"]] <- make.names(rownames(de_genes), unique = TRUE)
  }
  interesting_genes <- factor(annotated_genes %in% de_genes[["ID"]])
  names(interesting_genes) <- annotated_genes

  message("Checking the de_table for a p-value column:", pval_column)
  if (is.null(de_genes[[pval_column]])) {
    mf_GOdata <- new("topGOdata", ontology = "MF", allGenes = interesting_genes,
                     annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
    bp_GOdata <- new("topGOdata", ontology = "BP", allGenes = interesting_genes,
                     annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
    cc_GOdata <- new("topGOdata", ontology = "CC", allGenes = interesting_genes,
                     annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
  } else {
    pvals <- as.vector(as.numeric(de_genes[[pval_column]]))
    names(pvals) <- rownames(de_genes)
    mf_GOdata <- new("topGOdata", description = "MF", ontology = "MF", allGenes = pvals,
                     geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
    bp_GOdata <- new("topGOdata", description = "BP", ontology = "BP", allGenes = pvals,
                     geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
    cc_GOdata <- new("topGOdata", description = "CC", ontology = "CC", allGenes = pvals,
                     geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
  }

  mf_all <- cpdata[["mf_all"]]
  ## mf_enriched = cpdata[["mf_enriched"]]
  bp_all <- cpdata[["bp_all"]]
  ## bp_enriched = cpdata[["bp_enriched"]]
  cc_all <- cpdata[["cc_all"]]
  ## cc_enriched = cpdata[["cc_enriched"]]
  mf_all_ids <- mf_all@result[["ID"]]
  bp_all_ids <- bp_all@result[["ID"]]
  cc_all_ids <- cc_all@result[["ID"]]
  mf_all_scores <- mf_all@result[["p.adjust"]]
  bp_all_scores <- bp_all@result[["p.adjust"]]
  cc_all_scores <- cc_all@result[["p.adjust"]]
  names(mf_all_scores) <- mf_all_ids
  names(bp_all_scores) <- bp_all_ids
  names(cc_all_scores) <- cc_all_ids
  mf_included <- length(which(mf_all_scores <= score_limit))
  mf_tree_data <- try(suppressWarnings(
    topGO::showSigOfNodes(mf_GOdata, mf_all_scores, useInfo = "all",
                          sigForAll = TRUE, firstSigNodes = floor(mf_included * 1.5),
                          useFullNames = TRUE, plotFunction = hpgl_GOplot)))
  if (class(mf_tree_data)[1] == "try-error") {
    mf_tree <- NULL
  } else {
    mf_tree <- grDevices::recordPlot()
  }
  bp_included <- length(which(bp_all_scores <= score_limit))
  bp_tree_data <- try(suppressWarnings(
    topGO::showSigOfNodes(bp_GOdata, bp_all_scores, useInfo = "all",
                          sigForAll = TRUE, firstSigNodes = bp_included,
                          useFullNames = TRUE, plotFunction = hpgl_GOplot)))
  if (class(bp_tree_data)[1] == "try-error") {
    bp_tree <- NULL
  } else {
    bp_tree <- grDevices::recordPlot()
  }
  cc_included <- length(which(cc_all_scores <= score_limit))
  cc_tree_data <- try(suppressWarnings(
    topGO::showSigOfNodes(cc_GOdata, cc_all_scores, useInfo = "all",
                          sigForAll = TRUE, firstSigNodes = cc_included,
                          useFullNames = TRUE, plotFunction = hpgl_GOplot)))
  if (class(cc_tree_data)[1] == "try-error") {
    cc_tree <- NULL
  } else {
    cc_tree <- grDevices::recordPlot()
  }
  trees <- list(
    "MF_over" = mf_tree,
    "BP_over" = bp_tree,
    "CC_over" = cc_tree,
    "MF_overdata" = mf_tree_data,
    "BP_overdata" = bp_tree_data,
    "CC_overdata" = cc_tree_data)
  return(trees)
}

#' Print trees from topGO.
#'
#' The tree printing functionality of topGO is pretty cool, but difficult to get
#' set correctly.
#'
#' @param tg  Data from simple_topgo().
#' @param score_limit  Score limit to decide whether to add to the tree.
#' @param sigforall  Add scores to the tree?
#' @param do_mf_fisher_tree  Add the fisher score molecular function tree?
#' @param do_bp_fisher_tree  Add the fisher biological process tree?
#' @param do_cc_fisher_tree  Add the fisher cellular component tree?
#' @param do_mf_ks_tree  Add the ks molecular function tree?
#' @param do_bp_ks_tree  Add the ks biological process tree?
#' @param do_cc_ks_tree  Add the ks cellular component tree?
#' @param do_mf_el_tree  Add the el molecular function tree?
#' @param do_bp_el_tree  Add the el biological process tree?
#' @param do_cc_el_tree  Add the el cellular component tree?
#' @param do_mf_weight_tree  Add the weight mf tree?
#' @param do_bp_weight_tree  Add the bp weighted tree?
#' @param do_cc_weight_tree  Add the guess
#' @param parallel  Perform operations in parallel to speed this up?
#' @return Big list including the various outputs from topgo.
#' @seealso \pkg{topGO}
#' @export
topgo_trees <- function(tg, score_limit = 0.01, sigforall = TRUE,
                        do_mf_fisher_tree = TRUE, do_bp_fisher_tree = TRUE,
                        do_cc_fisher_tree = TRUE, do_mf_ks_tree = FALSE,
                        do_bp_ks_tree = FALSE, do_cc_ks_tree = FALSE,
                        do_mf_el_tree = FALSE, do_bp_el_tree = FALSE,
                        do_cc_el_tree = FALSE, do_mf_weight_tree = FALSE,
                        do_bp_weight_tree = FALSE, do_cc_weight_tree = FALSE,
                        parallel = FALSE) {
  mf_fisher_nodes <- mf_fisher_tree <- NULL
  if (isTRUE(do_mf_fisher_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["mf_fisher"]]) <= score_limit))
    mf_fisher_nodes <- try(sm(topGO::showSigOfNodes(
                                       tg[["results"]][["fmf_godata"]],
                                       topGO::score(tg[["results"]][["mf_fisher"]]),
                                       useInfo = "all",
                                       sigForAll = sigforall,
                                       firstSigNodes = included,
                                       useFullNames = TRUE,
                                       plotFunction = hpgl_GOplot)))
    if (class(mf_fisher_nodes)[1] != "try-error") {
      mf_fisher_tree <- try(grDevices::recordPlot())
    }
  }
  bp_fisher_nodes <- bp_fisher_tree <- NULL
  if (isTRUE(do_bp_fisher_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["bp_fisher"]]) <= score_limit))
    bp_fisher_nodes <- try(sm(topGO::showSigOfNodes(
                                       tg[["results"]][["fbp_godata"]],
                                       topGO::score(tg[["results"]][["bp_fisher"]]),
                                       useInfo = "all",
                                       sigForAll = sigforall,
                                       firstSigNodes = included,
                                       useFullNames = TRUE,
                                       plotFunction = hpgl_GOplot)))
    if (class(bp_fisher_nodes)[1] != "try-error") {
      bp_fisher_tree <- try(grDevices::recordPlot())
    }
  }
  cc_fisher_nodes <- cc_fisher_tree <- NULL
  if (isTRUE(do_cc_fisher_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["cc_fisher"]]) <= score_limit))
    cc_fisher_nodes <- try(sm(topGO::showSigOfNodes(
                                       tg[["results"]][["fcc_godata"]],
                                       topGO::score(tg[["results"]][["cc_fisher"]]),
                                       useInfo = "all",
                                       sigForAll = sigforall,
                                       firstSigNodes = included,
                                       useFullNames = TRUE,
                                       plotFunction = hpgl_GOplot)))
    if (class(cc_fisher_nodes)[1] != "try-error") {
      cc_fisher_tree <- try(grDevices::recordPlot())
    }
  }
  mf_ks_nodes <- mf_ks_tree <- NULL
  if (isTRUE(do_mf_ks_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["mf_ks"]]) <= score_limit))
    mf_ks_nodes <- try(sm(topGO::showSigOfNodes(
                                   tg[["results"]][["kmf_godata"]],
                                   topGO::score(tg[["results"]][["mf_ks"]]),
                                   useInfo = "all",
                                   sigForAll = sigforall,
                                   firstSigNodes = included,
                                   useFullNames = TRUE,
                                   plotFunction = hpgl_GOplot)))
    if (class(mf_ks_nodes)[1] != "try-error") {
      mf_ks_tree <- try(grDevices::recordPlot())
    }
  }
  bp_ks_nodes <- bp_ks_tree <- NULL
  if (isTRUE(do_bp_ks_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["bp_ks"]]) <= score_limit))
    bp_ks_nodes <- try(sm(topGO::showSigOfNodes(
                                   tg[["results"]][["kbp_godata"]],
                                   topGO::score(tg[["results"]][["bp_ks"]]),
                                   useInfo = "all",
                                   sigForAll = sigforall,
                                   firstSigNodes = included,
                                   useFullNames = TRUE,
                                   plotFunction = hpgl_GOplot)))
    if (class(bp_ks_nodes)[1] != "try-error") {
      bp_ks_tree <- try(grDevices::recordPlot())
    }
  }
  cc_ks_nodes <- cc_ks_tree <- NULL
  if (isTRUE(do_cc_ks_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["cc_ks"]]) <= score_limit))
    cc_ks_nodes <- try(sm(topGO::showSigOfNodes(
                                   tg[["results"]][["kcc_godata"]],
                                   topGO::score(tg[["results"]][["cc_ks"]]),
                                   useInfo = "all",
                                   sigForAll = sigforall,
                                   firstSigNodes = included,
                                   useFullNames = TRUE,
                                   plotFunction = hpgl_GOplot)))
    if (class(cc_ks_nodes)[1] != "try-error") {
      cc_ks_tree <- try(grDevices::recordPlot())
    }
  }
  mf_el_nodes <- mf_el_tree <- NULL
  if (isTRUE(do_mf_el_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["mf_el"]]) <= score_limit))
    mf_el_nodes <- try(sm(topGO::showSigOfNodes(
                                   tg[["results"]][["fmf_godata"]],
                                   topGO::score(tg[["results"]][["mf_el"]]),
                                   useInfo = "all",
                                   sigForAll = sigforall,
                                   firstSigNodes = included,
                                   useFullNames = TRUE,
                                   plotFunction = hpgl_GOplot)))
    if (class(mf_el_nodes)[1] != "try-error") {
      mf_el_tree <- try(grDevices::recordPlot())
    }
  }
  bp_el_nodes <- bp_el_tree <- NULL
  if (isTRUE(do_bp_el_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["bp_el"]]) <= score_limit))
    bp_el_nodes <- try(sm(topGO::showSigOfNodes(
                                   tg[["results"]][["fbp_godata"]],
                                   topGO::score(tg[["results"]][["bp_el"]]),
                                   useInfo = "all",
                                   sigForAll = sigforall,
                                   firstSigNodes = included,
                                   useFullNames = TRUE,
                                   plotFunction = hpgl_GOplot)))
    if (class(bp_el_nodes)[1] != "try-error") {
      bp_el_tree <- try(grDevices::recordPlot())
    }
  }
  cc_el_nodes <- cc_el_tree <- NULL
  if (isTRUE(do_cc_el_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["cc_el"]]) <= score_limit))
    cc_el_nodes <- try(sm(topGO::showSigOfNodes(
                                   tg[["results"]][["kcc_godata"]],
                                   topGO::score(tg[["results"]][["cc_el"]]),
                                   useInfo = "all",
                                   sigForAll = sigforall,
                                   firstSigNodes = included,
                                   useFullNames = TRUE,
                                   plotFunction = hpgl_GOplot)))
    if (class(cc_el_nodes)[1] != "try-error") {
      cc_el_tree <- try(grDevices::recordPlot())
    }
  }
  mf_weight_nodes <- mf_weight_tree <- NULL
  if (isTRUE(do_mf_weight_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["mf_weight"]]) <= score_limit))
    mf_weight_nodes <- try(sm(topGO::showSigOfNodes(
                                       tg[["results"]][["fmf_godata"]],
                                       topGO::score(tg[["results"]][["mf_weight"]]),
                                       useInfo = "all",
                                       sigForAll = sigforall,
                                       firstSigNodes = included,
                                       useFullNames = TRUE,
                                       plotFunction = hpgl_GOplot)))
    if (class(mf_weight_nodes)[1] != "try-error") {
      mf_weight_tree <- try(grDevices::recordPlot())
    }
  }
  bp_weight_nodes <- bp_weight_tree <- NULL
  if (isTRUE(do_bp_weight_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["bp_weight"]]) <= score_limit))
    bp_weight_nodes <- try(sm(topGO::showSigOfNodes(
                                       tg[["results"]][["fbp_godata"]],
                                       topGO::score(tg[["results"]][["bp_weight"]]),
                                       useInfo = "all",
                                       sigForAll = sigforall,
                                       firstSigNodes = included,
                                       useFullNames = TRUE,
                                       plotFunction = hpgl_GOplot)))
    if (class(bp_weight_nodes)[1] != "try-error") {
      bp_weight_tree <- try(grDevices::recordPlot())
    }
  }
  cc_weight_nodes <- cc_weight_tree <- NULL
  if (isTRUE(do_cc_weight_tree)) {
    included <- length(which(topGO::score(tg[["results"]][["cc_weight"]]) <= score_limit))
    cc_weight_nodes <- try(sm(topGO::showSigOfNodes(
                                       tg[["results"]][["fcc_godata"]],
                                       topGO::score(tg[["results"]][["cc_weight"]]),
                                       useInfo = "all",
                                       sigForAll = sigforall,
                                       firstSigNodes = included,
                                       useFullNames = TRUE,
                                       plotFunction = hpgl_GOplot)))
    if (class(cc_weight_nodes)[1] != "try-error") {
      cc_weight_tree <- try(grDevices::recordPlot())
    }
  }

  trees <- list(
    "mf_fisher_nodes" = mf_fisher_nodes,
    "bp_fisher_nodes" = bp_fisher_nodes,
    "cc_fisher_nodes" = cc_fisher_nodes,
    "mf_ks_nodes" = mf_ks_nodes,
    "bp_ks_nodes" = bp_ks_nodes,
    "cc_ks_nodes" = cc_ks_nodes,
    "mf_el_nodes" = mf_el_nodes,
    "bp_el_nodes" = bp_el_nodes,
    "cc_el_nodes" = cc_el_nodes,
    "mf_weight_nodes" = mf_weight_nodes,
    "bp_weight_nodes" = bp_weight_nodes,
    "cc_weight_nodes" = cc_weight_nodes,
    ## copying these here for consistent returns between goseq/cluster/topgo/gostats.
    "MF_over" = mf_fisher_tree,
    "BP_over" = bp_fisher_tree,
    "CC_over" = cc_fisher_tree,
    "MF_fisher_tree" = mf_fisher_tree,
    "BP_fisher_tree" = bp_fisher_tree,
    "CC_fisher_tree" = cc_fisher_tree,
    "MF_ks_tree" = mf_ks_tree,
    "BP_ks_tree" = bp_ks_tree,
    "CC_ks_tree" = cc_ks_tree,
    "MF_el_tree" = mf_el_tree,
    "BP_el_tree" = bp_el_tree,
    "CC_el_tree" = cc_el_tree,
    "MF_weight_tree" = mf_weight_tree,
    "BP_weight_tree" = bp_weight_tree,
    "CC_weight_tree" = cc_weight_tree)
  return(trees)
}

#' Take gostats data and print it on a tree as topGO does.
#'
#' This shoehorns gostats data into a format acceptable by topgo and uses it to
#' print pretty ontology trees showing the over represented ontologies.
#'
#' @param gostats_result Return from simple_gostats().
#' @param goid_map Mapping of IDs to GO in the Ramigo expected format.
#' @param score_limit Maximum score to include as 'significant'.
#' @param overwrite Overwrite the goid_map?
#' @param selector Function to choose differentially expressed genes in the data.
#' @param pval_column Column in the data to be used to extract pvalue scores.
#' @return plots! Trees! oh my!
#' @seealso \pkg{topGO} \pkg{gostats}
#' @export
gostats_trees <- function(gostats_result, goid_map = "id2go.map", score_limit = 0.01,
                          overwrite = FALSE, selector = "topDiffGenes",
                          pval_column = "adj.P.Val") {
  filename <- make_id2gomap(goid_map = goid_map, go_db = gostats_result[["go_db"]],
                            overwrite = overwrite)
  geneID2GO <- topGO::readMappings(file = goid_map)
  annotated_genes <- names(geneID2GO)
  de_genes <- gostats_result[["input"]]
  if (is.null(de_genes[["ID"]])) {
    de_genes[["ID"]] <- make.names(rownames(de_genes), unique = TRUE)
  }
  interesting_genes <- factor(annotated_genes %in% de_genes[["ID"]])
  names(interesting_genes) <- annotated_genes
  if (is.null(de_genes[[pval_column]])) {
    mf_GOdata <- new("topGOdata", ontology = "MF",
                     allGenes = interesting_genes, annot = topGO::annFUN.gene2GO,
                     gene2GO = geneID2GO)
    bp_GOdata <- new("topGOdata", ontology = "BP",
                     allGenes = interesting_genes, annot = topGO::annFUN.gene2GO,
                     gene2GO = geneID2GO)
    cc_GOdata <- new("topGOdata", ontology = "CC",
                     allGenes = interesting_genes, annot = topGO::annFUN.gene2GO,
                     gene2GO = geneID2GO)
  } else {
    pvals <- as.vector(de_genes[[pval_column]])
    names(pvals) <- rownames(de_genes)
    mf_GOdata <- new("topGOdata", description = "MF", ontology = "MF", allGenes = pvals,
                     geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
    bp_GOdata <- new("topGOdata", description = "BP", ontology = "BP", allGenes = pvals,
                     geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
    cc_GOdata <- new("topGOdata", description = "CC", ontology = "CC", allGenes = pvals,
                     geneSel = get(selector), annot = topGO::annFUN.gene2GO, gene2GO = geneID2GO)
  }
  mf_over <- gostats_result[["tables"]][["mf_over_all"]]
  mf_over_enriched_ids <- mf_over[["GOMFID"]]
  bp_over <- gostats_result[["tables"]][["bp_over_all"]]
  bp_over_enriched_ids <- bp_over[["GOBPID"]]
  cc_over <- gostats_result[["tables"]][["cc_over_all"]]
  cc_over_enriched_ids <- cc_over[["GOCCID"]]
  mf_over_enriched_scores <- mf_over[["Pvalue"]]
  names(mf_over_enriched_scores) <- mf_over_enriched_ids
  bp_over_enriched_scores <- bp_over[["Pvalue"]]
  names(bp_over_enriched_scores) <- bp_over_enriched_ids
  cc_over_enriched_scores <- cc_over[["Pvalue"]]
  names(cc_over_enriched_scores) <- cc_over_enriched_ids

  mf_avail_nodes <- as.list(mf_GOdata@graph@nodes)
  names(mf_avail_nodes) <- mf_GOdata@graph@nodes
  kidx <- names(mf_over_enriched_scores) %in% names(mf_avail_nodes)
  mf_over_nodes <- mf_over_enriched_scores[kidx]
  mf_over_included <- length(which(mf_over_nodes <= score_limit))
  mf_over_tree_data <- try(suppressWarnings(
    topGO::showSigOfNodes(mf_GOdata, mf_over_nodes, useInfo = "all",
                          sigForAll = TRUE, firstSigNodes = mf_over_included,
                          useFullNames = TRUE, plotFunction = hpgl_GOplot)))
  if (class(mf_over_tree_data) == "try-error") {
    message("There was an error generating the over MF tree.")
    mf_over_tree <- NULL
  } else {
    mf_over_tree <- grDevices::recordPlot()
  }

  bp_avail_nodes <- as.list(bp_GOdata@graph@nodes)
  names(bp_avail_nodes) <- bp_GOdata@graph@nodes
  kidx <- names(bp_over_enriched_scores) %in% names(bp_avail_nodes)
  bp_over_nodes <- bp_over_enriched_scores[kidx]
  bp_over_included <- length(which(bp_over_nodes <= score_limit))
  bp_over_tree_data <- try(suppressWarnings(
    topGO::showSigOfNodes(bp_GOdata, bp_over_nodes, useInfo = "all",
                          sigForAll = TRUE, firstSigNodes = bp_over_included,
                          useFullNames = TRUE, plotFunction = hpgl_GOplot)))
  if (class(bp_over_tree_data) == "try-error") {
    message("There was an error generating the over BP tree.")
    bp_over_tree <- NULL
  } else {
    bp_over_tree <- grDevices::recordPlot()
  }

  cc_avail_nodes <- as.list(cc_GOdata@graph@nodes)
  names(cc_avail_nodes) <- cc_GOdata@graph@nodes
  kidx <- names(cc_over_enriched_scores) %in% names(cc_avail_nodes)
  cc_over_nodes <- cc_over_enriched_scores[kidx]
  cc_over_included <- length(which(cc_over_nodes <= score_limit))
  cc_over_tree_data <- try(suppressWarnings(
    topGO::showSigOfNodes(cc_GOdata, cc_over_nodes, useInfo = "all",
                          sigForAll = TRUE, firstSigNodes = cc_over_included,
                          useFullNames = TRUE, plotFunction = hpgl_GOplot)))
  if (class(cc_over_tree_data) == "try-error") {
    message("There was an error generating the over CC tree.")
    cc_over_tree <- NULL
  } else {
    cc_over_tree <- grDevices::recordPlot()
  }

  trees <- list(
    "MF_over" = mf_over_tree,
    "BP_over" = bp_over_tree,
    "CC_over" = cc_over_tree,
    "MF_overdata" = mf_over_tree_data,
    "BP_overdata" = bp_over_tree_data,
    "CC_overdata" = cc_over_tree_data
    )
  return(trees)
}

## EOF
