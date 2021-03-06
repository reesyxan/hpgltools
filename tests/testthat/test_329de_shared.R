start <- as.POSIXlt(Sys.time())
library(testthat)
library(hpgltools)
context("29de_shared.R: Do the combined differential expression searches work?
  1234567890123456789012345678901234567890123456789012345678901\n")

pasilla <- new.env()
load("pasilla.rda", envir = pasilla)
pasilla_expt <- pasilla[["expt"]]
deseq <- new.env()
load("324_de_deseq.rda", envir = deseq)
edger <- new.env()
load("326_de_edger.rda", envir = edger)
limma <- new.env()
load("320_de_limma.rda", envir = limma)
basic <- new.env()
load("327_de_basic.rda", envir = basic)

## The following lines should not be needed any longer.
normalized_expt <- normalize_expt(pasilla_expt, transform = "log2", norm = "quant",
                                  convert = "cbcbcpm", filter = "cbcb", thresh = 1)

## Interestingly, doParallel does not work when run from packrat.
test_keepers <- list("treatment" = c("treated", "untreated"))
hpgl_all <- all_pairwise(pasilla_expt,
                         combined_excel = "excel_test.xlsx",
                         keepers = test_keepers)

combined_excel <- hpgl_all[["combined"]]
## 01
test_that("Does combine_de_tables create an excel file?", {
    expect_true(file.exists("excel_test.xlsx"))
})

hpgl_sva_result <- all_pairwise(pasilla_expt, model_batch = "sva", which_voom = "limma",
                                limma_method = "robust", edger_method = "long",
                                edger_test = "qlr")

expected <- deseq[["hpgl_deseq"]][["all_tables"]][["untreated_vs_treated"]]
table_order <- rownames(expected)
actual <- hpgl_all[["deseq"]][["all_tables"]][["untreated_vs_treated"]]
actual <- actual[table_order, ]
## 02
test_that("Do we get similar results to previous DE runs: (DESeq2)?", {
    expect_equal(expected, actual)
})

expected <- edger[["hpgl_edger"]][["all_tables"]][["untreated_vs_treated"]]
expected <- expected[table_order, ]
actual <- hpgl_all[["edger"]][["all_tables"]][["untreated_vs_treated"]]
actual <- actual[table_order, ]
## 03
test_that("Do we get similar results to previous DE runs: (edgeR)?", {
    expect_equal(expected, actual)
})

expected <- limma[["hpgl_limma"]][["all_tables"]][["untreated_vs_treated"]]
expected <- expected[table_order, ]
actual <- hpgl_all[["limma"]][["all_tables"]][["untreated_vs_treated"]]
actual <- actual[table_order, ]
## 04
test_that("Do we get similar results to previous DE runs: (limma)?", {
    expect_equal(expected, actual)
})

expected <- basic[["hpgl_basic"]][["all_tables"]][["untreated_vs_treated"]]
expected <- expected[table_order, ]
actual <- hpgl_all[["basic"]][["all_tables"]][["untreated_vs_treated"]]
actual <- actual[table_order, ]
## 05
test_that("Do we get similar results to previous DE runs: (basic)?", {
    expect_equal(expected, actual)
})

le <- hpgl_all[["comparison"]][["comp"]][[1]]
ld <- hpgl_all[["comparison"]][["comp"]][[2]]
ed <- hpgl_all[["comparison"]][["comp"]][[3]]
lb <- hpgl_all[["comparison"]][["comp"]][[4]]
eb <- hpgl_all[["comparison"]][["comp"]][[5]]
db <- hpgl_all[["comparison"]][["comp"]][[6]]
## 06
test_that("Are the comparisons between DE tools sufficiently similar? (limma/edger)", {
    expect_gt(le, 0.95)
})
## 07
test_that("Are the comparisons between DE tools sufficiently similar? (limma/deseq)", {
    expect_gt(ld, 0.95)
})
## 08
test_that("Are the comparisons between DE tools sufficiently similar? (edger/deseq)", {
    expect_gt(ed, 0.90)
})
## 09
test_that("Are the comparisons between DE tools sufficiently similar? (limma/basic)", {
    expect_gt(lb, 0.91)
})
## 10
test_that("Are the comparisons between DE tools sufficiently similar? (edger/basic)", {
    expect_gt(eb, 0.92)
})
## 11
test_that("Are the comparisons between DE tools sufficiently similar? (deseq/basic)", {
    expect_gt(db, 0.92)
})
combined_table <- combine_de_tables(hpgl_all, excel = FALSE)

expected_annotations <- c(
  "ensembltranscriptid", "ensemblgeneid",
  "description", "genebiotype",
  "cdslength", "chromosomename", "strand",
  "startposition", "endposition", "deseq_logfc",
  "deseq_adjp", "edger_logfc", "edger_adjp",
  "limma_logfc", "limma_adjp", "basic_nummed",
  "basic_denmed", "basic_numvar", "basic_denvar",
  "basic_logfc", "basic_t", "basic_p",
  "basic_adjp", "deseq_basemean", "deseq_lfcse",
  "deseq_stat", "deseq_p", "ebseq_fc",
  "ebseq_logfc", "ebseq_c1mean", "ebseq_c2mean",
  "ebseq_mean", "ebseq_var", "ebseq_postfc",
  "ebseq_ppee", "ebseq_ppde", "ebseq_adjp",
  "edger_logcpm", "edger_lr", "edger_p",
  "limma_ave", "limma_t", "limma_b",
  "limma_p", "limma_adjp_ihw", "deseq_adjp_ihw",
  "edger_adjp_ihw", "ebseq_adjp_ihw", "basic_adjp_ihw",
  "lfc_meta", "lfc_var", "lfc_varbymed", "p_meta",
  "p_var")
num_cols <- length(expected_annotations)
expected <- c(10153, num_cols)
actual <- dim(combined_table[["data"]][[1]])
## 12
test_that("Has the untreated/treated combined table been filled in?", {
    expect_equal(expected, actual)
})

sig_tables <- extract_significant_genes(combined_table,
                                        according_to = "all",
                                        excel = FALSE)
expected <- 123
actual <- nrow(sig_tables[["limma"]][["ups"]][[1]])
## 13
test_that("Are the limma significant ups expected?", {
    expect_equal(expected, actual)
})

expected <- 114
actual <- nrow(sig_tables[["limma"]][["downs"]][[1]])
## 14
test_that("Are the limma significant downs expected?", {
    expect_equal(expected, actual)
})

expected <- 141
actual <- nrow(sig_tables[["edger"]][["ups"]][[1]])
## 15
test_that("Are the edger significant ups expected?", {
    expect_equal(expected, actual)
})

expected <- 190
actual <- nrow(sig_tables[["edger"]][["downs"]][[1]])
## 16
test_that("Are the limma significant ups expected?", {
    expect_equal(expected, actual)
})

expected <- 113
actual <- nrow(sig_tables[["deseq"]][["ups"]][[1]])
## 17
test_that("Are the deseq significant ups expected?", {
    expect_equal(expected, actual)
})

expected <- 109
actual <- nrow(sig_tables[["deseq"]][["downs"]][[1]])
## 18
test_that("Are the deseq significant downs expected?", {
    expect_equal(expected, actual)
})

expected <- 40
actual <- nrow(sig_tables[["basic"]][["ups"]][[1]])
## 19
test_that("Are the basic significant ups expected?", {
    expect_gt(actual, expected)
})

expected <- 30
actual <- nrow(sig_tables[["basic"]][["downs"]][[1]])
## 20
test_that("Are the basic significant downs expected?", {
    expect_equal(actual, expected)
})

## I significantly changed the format of this function's output.
funkytown <- plot_num_siggenes(combined_table[["data"]][[1]])
expected <- c(11.02373, 10.91238, 10.80103, 10.68968, 10.57833, 10.46698)
actual <- as.numeric(head(funkytown[["up_data"]][[1]]))
## 21
test_that("Can we monitor changing significance (up_fc)?", {
    expect_equal(expected, actual, tolerance = 0.02)
})

expected <- c(-7.581495, -7.504914, -7.428333, -7.351752, -7.275172, -7.198591)
actual <- as.numeric(head(funkytown[["down_data"]][[1]]))
## 22
test_that("Can we monitor changing significance (up_fc)?", {
    expect_equal(expected, actual, tolerance = 0.02)
})

## We previously checked that we can successfully combine tables, let us now ensure that plots get created etc.
## Check that there are some venn plots in the excel workbook:
## expected <- "recordedplot"
## actual <- class(combined_excel[["venns"]][["treatment"]][["up_noweight"]])
## test_that("Are venn plots getting generated for the excel sheets?", {
##     expect_equal(expected, actual)
## })

expected <- c("gg", "ggplot")
actual <- class(combined_excel[["plots"]][["treatment"]][["limma_scatter_plots"]][["scatter"]])
## 23
test_that("Do we get a pretty limma scatter plot?", {
    expect_equal(expected, actual)
})
actual <- class(combined_excel[["plots"]][["treatment"]][["deseq_scatter_plots"]][["scatter"]])
## 24
test_that("Do we get a pretty deseq scatter plot?", {
    expect_equal(expected, actual)
})
actual <- class(combined_excel[["plots"]][["treatment"]][["edger_scatter_plots"]][["scatter"]])
## 25
test_that("Do we get a pretty edger scatter plot?", {
    expect_equal(expected, actual)
})

table <- "treatment"
actual <- colnames(combined_excel[["data"]][[table]])
## 26
test_that("Do we get expected columns from the excel sheet?", {
    expect_equal(expected_annotations, actual)
})

## Test that we can extract the significant genes and get pretty graphs
significant_excel <- extract_significant_genes(combined_excel,
                                               excel = "excel_test_sig.xlsx")
## 27
test_that("Does combine_de_tables create an excel file?", {
    expect_true(file.exists("excel_test_sig.xlsx"))
})

## How many significant up genes did limma find?
actual <- dim(significant_excel[["limma"]][["ups"]][[table]])
expected <- c(114, num_cols)
## 28
test_that("Is the number of significant up genes as expected? (limma)", {
    expect_equal(expected, actual)
})

actual <- dim(significant_excel[["deseq"]][["ups"]][[table]])
expected <- c(109, num_cols)
## 29
test_that("Is the number of significant up genes as expected? (deseq)", {
    expect_equal(expected, actual)
})

actual <- dim(significant_excel[["edger"]][["ups"]][[table]])
expected <- c(190, num_cols)
## 30
test_that("Is the number of significant up genes as expected? (edger)", {
    expect_equal(expected, actual)
})

actual <- dim(significant_excel[["limma"]][["downs"]][[table]])
expected <- c(123, num_cols)
## 31
test_that("Is the number of significant down genes as expected? (limma)", {
    expect_equal(expected, actual)
})

actual <- dim(significant_excel[["deseq"]][["downs"]][[table]])
expected <- c(113, num_cols)
## 32
test_that("Is the number of significant down genes as expected? (deseq)", {
    expect_equal(expected, actual)
})

actual <- dim(significant_excel[["edger"]][["downs"]][[table]])
expected <- c(141, num_cols)
## 33
test_that("Is the number of significant down genes as expected? (edger)", {
  expect_equal(expected, actual)
})

actual <- dim(significant_excel[["ebseq"]][["downs"]][[table]])
expected <- c(90, num_cols)
## 34
test_that("Is the number of significant down genes as expected? (ebseq)", {
  expect_equal(expected, actual)
})

actual <- class(significant_excel[["sig_bar_plots"]][["limma"]])[[1]]
expected <- "gg"
## 35
test_that("Are the significance bar plots generated? (limma)",  {
    expect_equal(expected, actual)
})

## Check to make sure that if we specify a direction for the comparison, that it is maintained.
forward_keepers <- list("treatment" = c("treated", "untreated"))
reverse_keepers <- list("treatment" = c("untreated", "treated"))
reverse_combined_excel <- combine_de_tables(hpgl_all, keepers = reverse_keepers, excel = FALSE)
forward_combined_excel <- combine_de_tables(hpgl_all, keepers = forward_keepers, excel = FALSE)
forward_fold_changes <- forward_combined_excel[["data"]][[table]][["limma_logfc"]]
expected <- sort(forward_fold_changes)
actual <- sort(reverse_combined_excel[["data"]][[table]][["limma_logfc"]] * -1)
## 36
test_that("When we reverse a combined_de_tables(), we get reversed results? (limma)", {
    expect_equal(expected, actual)
})

expected <- sort(forward_combined_excel[["data"]][[table]][["edger_logfc"]])
actual <- sort(reverse_combined_excel[["data"]][[table]][["edger_logfc"]] * -1)
## 37
test_that("When we reverse a combined_de_tables(), we get reversed results? (edger)", {
    expect_equal(expected, actual)
})

expected <- sort(forward_combined_excel[["data"]][[table]][["deseq_logfc"]])
actual <- sort(reverse_combined_excel[["data"]][[table]][["deseq_logfc"]] * -1)
## 38
test_that("When we reverse a combined_de_tables(), we get reversed results? (deseq)", {
    expect_equal(expected, actual)
})

expected <- sort(forward_combined_excel[["data"]][[table]][["basic_logfc"]])
actual <- sort(reverse_combined_excel[["data"]][[table]][["basic_logfc"]] * -1)
## 39
test_that("When we reverse a combined_de_tables(), we get reversed results? (basic)", {
    expect_equal(expected, actual)
})

expected <- sort(forward_combined_excel[["data"]][[table]][["limma_adjp"]])
actual <- sort(reverse_combined_excel[["data"]][[table]][["limma_adjp"]])
## 40
test_that("When we reverse a combined_de_tables(), we get appropriate p-values? (limma)", {
    expect_equal(expected, actual)
})

expected <- sort(forward_combined_excel[["data"]][[table]][["edger_adjp"]])
actual <- sort(reverse_combined_excel[["data"]][[table]][["edger_adjp"]])
## 41
test_that("When we reverse a combined_de_tables(), we get appropriate p-values? (edger)", {
    expect_equal(expected, actual)
})

expected <- sort(forward_combined_excel[["data"]][[table]][["deseq_adjp"]])
actual <- sort(reverse_combined_excel[["data"]][[table]][["deseq_adjp"]])
## 42
test_that("When we reverse a combined_de_tables(), we get appropriate p-values? (deseq)", {
    expect_equal(expected, actual)
})

## Make sure that MA plots from combined tables are putting the logFCs in the right direction
forward_plot <- extract_de_plots(forward_combined_excel, type = "limma")[["ma"]]
reverse_plot <- extract_de_plots(reverse_combined_excel, type = "limma")[["ma"]]
expected <- sort(forward_plot[["df"]][["logfc"]])
actual <- sort(reverse_plot[["df"]][["logfc"]] * -1)
## 43
test_that("Plotting an MA plot from a combined DE table provides logFCs in the correct orientation?", {
    expect_equal(expected, actual)
})

## See that we can compare different analysis types
combined_sva <- combine_de_tables(hpgl_sva_result, excel = NULL, keepers = test_keepers)
sva_batch_test <- compare_de_results(combined_excel, combined_sva)
expected <- 0.71
actual <- sva_batch_test[["result"]][["limma"]][[table]][["logfc"]]
## 44
test_that("Do limma with combat and sva agree vis a vis logfc?", {
    expect_gt(actual, expected)
})

expected <- 0.97
actual <- sva_batch_test[["result"]][["deseq"]][[table]][["logfc"]]
## 45
test_that("Do deseq with combat and sva agree vis a vis logfc?", {
    expect_gt(actual, expected)
})

expected <- 0.97
actual <- sva_batch_test[["result"]][["edger"]][[table]][["logfc"]]
## 46
test_that("Do edger with combat and sva agree vis a vis logfc?", {
    expect_gt(actual, expected)
})

## See if the intersection between limma, deseq, and edger is decent.
test_intersect <- intersect_significant(combined_sva, excel = NULL)
expected <- 98
actual <- nrow(test_intersect[["ups"]][[table]][["data"]][["all"]])
## 47
test_that("Do we get the expected number of agreed upon significant genes between edger/deseq/limma?", {
    expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["downs"]][[table]][["data"]][["all"]])
expected <- 102
## 48
test_that("Ibid, but in the down direction?", {
    expect_equal(actual, expected)
})
actual <- sum(nrow(test_intersect[["ups"]][[table]][["data"]][["limma"]]) +
              nrow(test_intersect[["ups"]][[table]][["data"]][["edger"]]) +
              nrow(test_intersect[["ups"]][[table]][["data"]][["deseq"]]))
expected <- 77
## 49
test_that("Are there very few genes observed without the others?", {
    expect_equal(actual, expected)
})
actual <- sum(nrow(test_intersect[["downs"]][[table]][["data"]][["limma"]]) +
              nrow(test_intersect[["downs"]][[table]][["data"]][["edger"]]) +
              nrow(test_intersect[["downs"]][[table]][["data"]][["deseq"]]))
expected <- 108
## 50
test_that("Ibid, but down?", {
    expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["ups"]][[table]][["data"]][["limma_edger"]])
expected <- 29
## 51
test_that("Do limma and edger have some genes in common? (up)", {
    expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["downs"]][[table]][["data"]][["limma_edger"]])
expected <- 10
## 52
test_that("Do limma and edger have some genes in common? (down)", {
    expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["ups"]][[table]][["data"]][["limma_deseq"]])
expected <- 0
## 53
test_that("Do limma and deseq have some genes in common? (up)", {
    expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["downs"]][[table]][["data"]][["limma_deseq"]])
expected <- 4
## 54
test_that("Do limma and deseq have some genes in common? (down)", {
    expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["ups"]][[table]][["data"]][["deseq_edger"]])
expected <- 14
## 55
test_that("Do edger and deseq have some genes in common? (up)", {
    expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["downs"]][[table]][["data"]][["deseq_edger"]])
expected <- 4
## 56
test_that("Do edger and deseq have some genes in common? (down)", {
  expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["ups"]][[table]][["data"]][["all"]])
expected <- 98
## 57
test_that("Do all methods have some genes in common? (up)", {
  expect_equal(actual, expected)
})
actual <- nrow(test_intersect[["downs"]][[table]][["data"]][["all"]])
expected <- 102
## 58
test_that("Do all methods have some genes in common? (down)", {
  expect_equal(actual, expected)
})

end <- as.POSIXlt(Sys.time())
elapsed <- round(x = as.numeric(end - start))
message("\nFinished 29de_shared.R in ", elapsed,  " seconds.")
