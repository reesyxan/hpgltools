## Note to self, I think for future ggplot2 plots, I must start by creating the data frame
## Then cast every column in it explicitly, and only then invoke ggplot(data=df ...)

## If I see something like:
## 'In sample_data$mean = means : Coercing LHS to a list'
## That likely means that I was supposed to have data in the
## data.frame() format, but instead it is a matrix.  In functions
## where this is a danger, it is a likely good idea to cast it as a
## data frame.

#' Look at the range of the data for a plot and use it to suggest if a plot
#' should be on log scale.
#'
#' There are a bunch of plots which often-but-not-always benefit from being
#' displayed on a log scale rather than base 10.  This is a quick and dirty
#' heuristic which suggests the appropriate scale.  If the data 'should' be on
#' the log scale and it has 0s, then they are moved to 1 so that when logged
#' they will return to 0.  Similarly, if there are negative numbers and the
#' intended scale is log, then this will set values less than 0 to zero to avoid
#' imaginary numbers.
#'
#' @param data  Data to plot.
#' @param scale  If known, this will be used to define what (if any) values to
#'   change.
#' @param max_data  Define the upper limit for the heuristic.
#' @param min_data  Define the lower limit for the heuristic.
check_plot_scale <- function(data, scale=NULL, max_data=10000, min_data=10) {
  if (max(data) > max_data & min(data) < min_data) {
    message("This data will benefit from being displayed on the log scale.")
    message("If this is not desired, set scale='raw'")
    scale <- "log"
    negative_idx <- data < 0
    if (sum(negative_idx) > 0) {
      message("Some data are negative.  We are on log scale, setting them to 0.")
      data[negative_idx] <- 0
      message("Changed ", sum(negative_idx), " negative features.")
    }
    zero_idx <- data == 0
    if (sum(zero_idx) > 0) {
      message("Some entries are 0.  We are on log scale, adding 1 to the data.")
      data <- data + 1
      message("Changed ", sum(zero_idx), " zero count features.")
    }
  } else {
    scale <- "raw"
  }
  retlist <- list(
    "data" = data,
    "scale" = scale)
  return(retlist)
}

#' Simplify plotly ggplot conversion so that there are no shenanigans.
#'
#' I am a fan of ggplotly, but its conversion to an html file is not perfect.
#' This hopefully will get around the most likely/worst problems.
#'
#' @param gg Plot from ggplot2.
#' @param filename  Output filename.
#' @param selfcontained  htmlwidgets: Return the plot as a self-contained file
#'   with images re-encoded base64.
#' @param libdir htmlwidgets: Directory into which to put dependencies.
#' @param background  htmlwidgets: String for the background of the image.
#' @param title  htmlwidgets: Title of the page!
#' @param knitrOptions  htmlwidgets: I am not a fan of camelCase, but
#'   nonetheless, options from knitr for htmlwidgets.
#' @param ... Any remaining elipsis options are passed to ggplotly.
#' @return The final output filename
ggplt <- function(gg, filename="ggplot.html",
                  selfcontained=TRUE, libdir=NULL, background="white",
                  title=class(gg)[[1]], knitrOptions=list(), ...) {
  base <- basename(filename)
  dir <- dirname(filename)
  out <- plotly::ggplotly(gg, ...)
  widget <- htmlwidgets::saveWidget(
                           plotly::as_widget(out), base, selcontained=selfcontained,
                           libdir=libdir, background=background, title=title,
                           knitrOptions=knitrOptions)
  if (dir != ".") {
    final <- file.path(dir, base)
    moved <- file.rename(base, final)
  }
  return(final)
}

#' Make lots of graphs!
#'
#' Plot out a set of metrics describing the state of an experiment
#' including library sizes, # non-zero genes, heatmaps, boxplots,
#' density plots, pca plots, standard median distance/correlation, and
#' qq plots.
#'
#' @param expt  an expt to process
#' @param cormethod   the correlation test for heatmaps.
#' @param distmethod define the distance metric for heatmaps.
#' @param title_suffix   text to add to the titles of the plots.
#' @param qq   include qq plots?
#' @param ma   include pairwise ma plots?
#' @param gene_heat  Include a heatmap of the gene expression data?
#' @param ... extra parameters optionally fed to the various plots
#' @return a loooong list of plots including the following:
#' \enumerate{
#'   \item nonzero = a ggplot2 plot of the non-zero genes vs library size
#'   \item libsize = a ggplot2 bar plot of the library sizes
#'   \item boxplot = a ggplot2 boxplot of the raw data
#'   \item corheat = a recordPlot()ed pairwise correlation heatmap of the raw data
#'   \item smc = a recordPlot()ed view of the standard median pairwise correlation of the raw data
#'   \item disheat = a recordPlot()ed pairwise euclidean distance heatmap of the raw data
#'   \item smd = a recordPlot()ed view of the standard median pairwise distance of the raw data
#'   \item pcaplot = a recordPlot()ed PCA plot of the raw samples
#'   \item pcatable = a table describing the relative contribution of condition/batch of the raw data
#'   \item pcares =  a table describing the relative contribution of condition/batch of the raw data
#'   \item pcavar = a table describing the variance of the raw data
#'   \item qq = a recordPlotted() view comparing the quantile/quantiles between
#'      the mean of all data and every raw sample
#'   \item density = a ggplot2 view of the density of each raw sample (this is
#'      complementary but more fun than a boxplot)
#' }
#' @seealso \pkg{Biobase} \pkg{ggplot2} \pkg{grDevices} \pkg{gplots}
#'   \code{\link[Biobase]{exprs}} \code{\link{hpgl_norm}}
#'   \code{\link{plot_nonzero}} \code{\link{plot_libsize}}
#'   \code{\link{plot_boxplot}} \code{\link{plot_corheat}} \code{\link{plot_sm}}
#'   \code{\link{plot_disheat}} \code{\link{plot_pca}} \code{\link{plot_qq_all}}
#'   \code{\link{plot_pairwise_ma}}
#' @examples
#' \dontrun{
#'  toomany_plots <- graph_metrics(expt)
#'  toomany_plots$pcaplot
#'  norm <- normalize_expt(expt, convert="cpm", batch=TRUE, filter_low=TRUE,
#'                         transform="log2", norm="rle")
#'  holy_asscrackers <- graph_metrics(norm, qq=TRUE, ma=TRUE)
#' }
#' @export
graph_metrics <- function(expt, cormethod="pearson", distmethod="euclidean",
                          title_suffix=NULL, qq=FALSE, ma=FALSE, gene_heat=FALSE,
                          ...) {
  arglist <- list(...)
  if (!exists("expt", inherits=FALSE)) {
    stop("The input data does not exist.")
  }
  dev_length <- length(dev.list())
  if (dev_length > 1) {
    message("Hey! You have ", dev_length,
            " plotting devices open, this might be in error.")
  }
  ## First gather the necessary data for the various plots.
  old_options <- options(scipen=10)
  nonzero_title <- "Non zero genes"
  libsize_title <- "Library sizes"
  boxplot_title <- "Boxplot"
  corheat_title <- "Correlation heatmap"
  smc_title <- "Standard Median Correlation"
  disheat_title <- "Distance heatmap"
  smd_title <- "Standard Median Distance"
  pca_title <- "Principle Component Analysis"
  tsne_title <- "T-SNE Analysis"
  dens_title <- "Density plot"
  cv_title <- "Coefficient of variance plot"
  topn_title <- "Top-n representation"
  if (!is.null(title_suffix)) {
    nonzero_title <- glue("{nonzero_title}: {title_suffix}")
    libsize_title <- glue("{libsize_title}: {title_suffix}")
    boxplot_title <- glue("{boxplot_title}: {title_suffix}")
    corheat_title <- glue("{corheat_title}: {title_suffix}")
    smc_title <- glue("{smc_title}: {title_suffix}")
    disheat_title <- glue("{disheat_title}: {title_suffix}")
    smd_title <- glue("{smd_title}: {title_suffix}")
    pca_title <- glue("{pca_title}: {title_suffix}")
    tsne_title <- glue("{tsne_title}:  {title_suffix}")
    dens_title <- glue("{dens_title}: {title_suffix}")
    cv_title <- glue("{cv_title}: {title_suffix}")
    topn_title <- glue("{topn_title}: {title_suffix}")
  }

  ## I am putting the ... arguments on a separate line so that I can check that
  ## each of these functions is working properly in an interactive session.
  message("Graphing number of non-zero genes with respect to CPM by library.")
  nonzero <- try(plot_nonzero(expt, title=nonzero_title,
                              ...))
  message("Graphing library sizes.")
  libsize <- try(plot_libsize(expt, title=libsize_title,
                              ...))
  message("Graphing a boxplot.")
  boxplot <- try(plot_boxplot(expt, title=boxplot_title,
                              ...))
  message("Graphing a correlation heatmap.")
  corheat <- try(plot_corheat(expt, method=cormethod, title=corheat_title,
                              ...))
  message("Graphing a standard median correlation.")
  smc <- try(plot_sm(expt, method=cormethod, title=smc_title,
                     ...))
  message("Graphing a distance heatmap.")
  disheat <- try(plot_disheat(expt, method=distmethod, title=disheat_title,
                              ...))
  message("Graphing a standard median distance.")
  smd <- try(plot_sm(expt, method=distmethod, title=smd_title,
                     ...))
  message("Graphing a PCA plot.")
  pca <- try(plot_pca(expt, title=pca_title,
                      ...))
  message("Graphing a T-SNE plot.")
  tsne <- try(plot_tsne(expt, title=tsne_title,
                        ...))
  message("Plotting a density plot.")
  density <- try(plot_density(expt, title=dens_title,
                              ...))
  message("Plotting a CV plot.")
  cv <- try(plot_variance_coefficients(expt, title=dens_title,
                                       ...))
  message("Plotting the representation of the top-n genes.")
  topn <- try(plot_topn(expt, title=topn_title,
                        ...))
  message("Printing a color to condition legend.")
  legend <- try(plot_legend(expt))

  qq_logs <- NULL
  qq_ratios <- NULL
  if (isTRUE(qq)) {
    message("QQ plotting!")
    qq_plots <- try(suppressWarnings(plot_qq_all(expt, ...)))
    qq_logs <- qq_plots[["logs"]]
    qq_ratios <- qq_plots[["ratios"]]
  }

  ma_plots <- NULL
  if (isTRUE(ma)) {
    message("Many MA plots!")
    ma_plots <- try(suppressWarnings(plot_pairwise_ma(expt, ...)))
  }

  gene_heatmap <- NULL
  if (isTRUE(gene_heat)) {
    message("gene heatmap!")
    gene_heatmap <- try(suppressWarnings(plot_sample_heatmap(expt, ...)))
  }

  ret_data <- list(
    "boxplot" = boxplot,
    "corheat" = corheat[["plot"]],
    "density" = density[["plot"]],
    "density_table" = density[["table"]],
    "disheat" = disheat[["plot"]],
    "gene_heatmap" = gene_heatmap,
    "legend" = legend[["plot"]],
    "legend_colors" = legend[["colors"]],
    "libsize" = libsize[["plot"]],
    "libsizes" = libsize[["table"]],
    "libsize_summary" = libsize[["summary"]],
    "ma" = ma_plots,
    "nonzero" = nonzero[["plot"]],
    "nonzero_table" = nonzero[["table"]],
    "qqlog" = qq_logs,
    "qqrat" = qq_ratios,
    "smc" = smc,
    "smd" = smd,
    "cvplot" = cv[["plot"]],
    "topnplot" = topn[["plot"]],
    "pc_summary" = pca[["residual_df"]],
    "pc_propvar" = pca[["prop_var"]],
    "pc_plot" = pca[["plot"]],
    "pc_table" = pca[["table"]],
    "tsne_summary" = tsne[["residual_df"]],
    "tsne_propvar" = tsne[["prop_var"]],
    "tsne_plot" = tsne[["plot"]],
    "tsne_table" = tsne[["table"]]
  )
  new_options <- options(old_options)
  return(ret_data)
}

#' Scab the legend from a PCA plot and print it alone
#'
#' This way I can have a legend object to move about.
#'
#' @param stuff This can take either a ggplot2 pca plot or some data from which to make one.
#' @return A legend!
#' @export
plot_legend <- function(stuff) {
  plot <- NULL
  if (class(stuff)[[1]] == "gg") {
    ## Then assume it is a pca plot
    plot <- stuff
  } else {
    plot <- plot_pca(stuff)[["plot"]]
  }

  tmp <- ggplot2::ggplot_gtable(ggplot2::ggplot_build(plot))
  leg <- which(sapply(tmp[["grobs"]], function(x) x[["name"]]) == "guide-box")
  legend <- tmp[["grobs"]][[leg]]
  grid::grid.newpage()
  grid::grid.draw(legend)
  legend_plot <- grDevices::recordPlot()
  ret <- list(
    colors = plot[["data"]][, c("condition", "batch", "colors")],
    plot = legend_plot)
  return(ret)
}

## I thought multiplot() was a part of ggplot(), but no, weird:
## http://stackoverflow.com/questions/24387376/r-wired-error-could-not-find-function-multiplot
## Also found at:
## http://www.cookbook-r.com/Graphs/Multiple_graphs_on_one_page_%28ggplot2%29/
#' Make a grid of plots.
#'
#' @param plots  a list of plots
#' @param file  a file to write to
#' @param cols   the number of columns in the grid
#' @param layout  set the layout specifically
#' @return a multiplot!
#' @export
plot_multiplot <- function(plots, file, cols=NULL, layout=NULL) {
  ## Make a list from the ... arguments and plotlist
  ##  plots <- c(list(...), plotlist)
  numPlots <- length(plots)
  if (is.null(cols)) {
    cols <- ceiling(sqrt(length(plots)))
  }
  ## If layout is NULL, then use 'cols' to determine layout
  if (is.null(layout)) {
    ## Make the panel
    ## ncol: Number of columns of plots
    ## nrow: Number of rows needed, calculated from # of cols
    layout <- matrix(seq(1, cols * ceiling(numPlots / cols)),
                     ncol=cols, nrow=ceiling(numPlots / cols))
  }

  if (numPlots==1) {
    print(plots[[1]])
  } else {
    ## Set up the page
    grid::grid.newpage()
    grid::pushViewport(grid::viewport(
                               layout=grid::grid.layout(nrow(layout), ncol(layout))))
    ## Make each plot, in the correct location
    for (i in 1:numPlots) {
      ## Get the i,j matrix positions of the regions that contain this subplot
      matchidx <- as.data.frame(which(layout == i, arr.ind=TRUE))
      print(plots[[i]], vp=grid::viewport(layout.pos.row=matchidx[["row"]],
                                          layout.pos.col=matchidx[["col"]]))
    }
  }
}

## EOF
