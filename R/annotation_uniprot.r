#' Read a uniprot text file and extract as much information from it as possible.
#'
#' I spent entirely too long fighting with Uniprot.ws, finally got mad and wrote this.
#'
#' @param file  Uniprot file to read and parse
#' @param savefile  Do a save?
#' @return  Big dataframe of annotation data.
#' @export
load_uniprot_annotations <- function(file, savefile=TRUE) {
  ## file <-  "uniprot_3AUP000001584.txt.gz"
  if (isTRUE(savefile)) {
    savefile <- "uniprot.rda"
  }
  ##if (!is.null(savefile) & savefile != NULL) {
  ##  if (file.exists(savefile)) {
  ##    uniprot_data <- new.env()
  ##    loaded <- load(savefile, envir=retlist)
  ##    uniprot_data <- uniprot_data[["uniprot_data"]]
  ##    return(retlist)
  ##  }
  ##}
  read_vec <- readr::read_lines(file, progress=TRUE)
  gene_num <- 0
  ## Vectors for those elements which will only have 1 answer
  many_ids <- list()
  id_types <- c(
    "primary_id", "amino_acids", "primary_accessions", "amino_acids", "recnames", "loci", "orfnames",
    "shortnames", "synonyms", "uniprot_accessions", "embl", "pir", "refseq",
    "proteinmodelportals", "smr", "string", "pax", "pride", "ensbact", "geneid", "kegg",
    "tuberculist", "eggnog", "ko", "oma", "phylome", "unipathway", "proteome", "go", "cdd",
    "gene3d", "hamap", "interpro", "panther", "pirsf", "prints", "pfam", "supfam", "tigrfam",
    "prosite", "mw", "aa_sequence"
  )
  reading_sequence <- FALSE
  bar <- utils::txtProgressBar(style=3)
  for (i in 1:length(read_vec)) {
    pct_done <- i / length(read_vec)
    utils::setTxtProgressBar(bar, pct_done)
    line <- read_vec[i]
    ## Start by skipping field types that we will never use.
    if (grepl(pattern="^(DT|OS|OC|OX|RN|RA|RT|RP|RX|CC|PE|KW|FT|SQ)\\s+", x=line)) {
      next
    }
    ## The master ID:
    ## Example: ID   3MGH_MYCTU              Reviewed;         203 AA.
    if (grepl(pattern="^ID\\s+", x=line)) {
      gene_num <- gene_num + 1
      ## Initialize the ith element of our various data structures.
      for (type in id_types) {
        many_ids[[type]][gene_num] <- ""
      }
      ## Done initializing, now fill in the data.
      material <- strsplit(x=line, split="\\s+")[[1]]
      gene_id <- material[2]
      many_ids[["primary_id"]][gene_num] <- gene_id
      many_ids[["amino_acids"]][gene_num] <- material[4]
      next
    }
    ## Now pull the primary uniprot accesstions
    ## Example: AC   P9WJP7; L0TAC1; O33190; P65412;
    if (grepl(pattern="^AC\\s+", x=line)) {
      tmp_ids <- gsub(pattern=";", replacement="", x=strsplit(x=line, split="\\s+")[[1]])
      many_ids[["primary_accessions"]][gene_num] <- tmp_ids[2]
      tmp_ids <- toString(tmp_ids[2:length(tmp_ids)])
      many_ids[["uniprot_accessions"]][gene_num] <- tmp_ids
      next
    }
    ## Get the record names if available
    ## Example: DE   RecName: Full=Putative 3-methyladenine DNA glycosylase {ECO:0000255|HAMAP-Rule:MF_00527};
    ##          DE            EC=3.2.2.- {ECO:0000255|HAMAP-Rule:MF_00527};
    if (grepl(pattern="DE\\s+RecName:", x=line)) {
      tmp_ids <- gsub(pattern="^.*Full=(.*?);.*$", replacement="\\1", x=line)
      many_ids[["recnames"]][gene_num] <- tmp_ids
      next
    }
    ## The GN field has a few interesting pieces of information and I think makes the primary link
    ## between uniprot and the IDs available at genbank, ensembl, microbesonline, etc.
    ## We may find one or more of the above fields in the GN, so I should take into account
    ## the various possible iterations.
    ## Example: GN   Name=pgl; Synonyms=devB; OrderedLocusNames=Rv1445c;
    ##          GN   ORFNames=MTCY493.09;
    if (grepl(pattern="^GN\\s+", x=line)) {
      pat <- "^GN\\s+.*OrderedLocusNames=(.*?);.*$"
      if (grepl(pattern=pat, x=line)) {
        ## message(paste0("Got a locusname on line ", i, " for gene number ", gene_num)) ## i=565 is first interesting one.
        tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
        tmp_ids <- gsub(pattern="^(.*?),.*", replacement="\\1", x=tmp_ids)
        many_ids[["loci"]][gene_num] <- gsub(pattern="^(.*?) \\{.*", replacement="\\1", x=tmp_ids)
      }
      pat <- "^GN\\s+.*ORFNames=(.*?);.*$"
      if (grepl(pattern=pat, x=line)) {
        many_ids[["orfnames"]][gene_num] <- gsub(pattern=pat, replacement="\\1", x=line)
      }
      pat <- "^GN\\s+.*Name=(.*?);.*$"
      if (grepl(pattern=pat, x=line)) {
        tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
        many_ids[["shortnames"]][gene_num] <- gsub(pattern="^(.*?) .*", replacement="\\1", x=tmp_ids)
      }
      pat <- "^GN\\s+.*Synonyms=(.*?);.*$"
      if (grepl(pattern=pat, x=line)) {
        many_ids[["synonyms"]][gene_num] <- gsub(pattern=pat, replacement="\\1", x=line)
      }
      next
    }
    ## The DR field contains mappings to many other databases
    ## Sadly, it too is quite a mess
    ## This stanza looks for EMBL IDs:
    ## Example: DR   EMBL; AL123456; CCP44204.1; -; Genomic_DNA.
    pat_prefix <- "^DR\\s+"
    dot_suffix <- "; (.*?)\\.$"
    dash_suffix <- "; (.*?);( \\-.*)$"
    pat <- paste0(pat_prefix, "EMBL", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["embl"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "PIR", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["pir"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "RefSeq", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      if (many_ids[["refseq"]][gene_num] == "") {
        many_ids[["refseq"]][gene_num] <- tmp_ids
      } else {
        many_ids[["refseq"]][gene_num] <- toString(c(many_ids[["refseq"]][gene_num], tmp_ids))
      }
      next
    }
    pat <- paste0(pat_prefix, "ProteinModelPortal", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["proteinmodelportals"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "SMR", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\1", x=tmp_ids)
      many_ids[["smr"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "STRING", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["string"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "PaxDB", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["pax"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "PRIDE", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["pride"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "EnsemblBacteria", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["ensbact"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "GeneID", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["geneid"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "KEGG", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["kegg"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "TubercuList", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["tuberculist"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "eggNOG", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      if (many_ids[["eggnog"]][gene_num] == "") {
        many_ids[["eggnog"]][gene_num] <- tmp_ids
      } else {
        many_ids[["eggnog"]][gene_num] <- toString(c(many_ids[["eggnog"]][gene_num], tmp_ids))
      }
      next
    }
    pat <- paste0(pat_prefix, "KO", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["ko"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "OMA", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["oma"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "PhylomeDB", dash_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["phylome"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "UniPathway", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["unipathway"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "Proteomes", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["proteome"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "GO", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      if (many_ids[["go"]][gene_num] == "") {
        many_ids[["go"]][gene_num] <- tmp_ids
      } else {
        many_ids[["go"]][gene_num] <- toString(c(many_ids[["go"]][gene_num], tmp_ids))
      }
      next
    }
    pat <- paste0(pat_prefix, "CDD", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["cdd"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "Gene3D", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["gene3d"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "HAMAP", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["hamap"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "InterPro", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      if (many_ids[["interpro"]][gene_num] == "") {
        many_ids[["interpro"]][gene_num] <- tmp_ids
      } else {
        many_ids[["interpro"]][gene_num] <- toString(c(many_ids[["interpro"]][gene_num], tmp_ids))
      }
      next
    }
    pat <- paste0(pat_prefix, "PANTHER", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["panther"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "Pfam", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["pfam"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "PIRSF", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["pirsf"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "PRINTS", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["prints"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "SUPFAM", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["supfam"]][gene_num] <- tmp_ids
      next
    }
    pat <- paste0(pat_prefix, "TIGRFAMs", dot_suffix)
    if (grepl(pattern=pat, x=line)) {
      tmp_ids <- gsub(pattern=pat, replacement="\\1", x=line)
      tmp_ids <- gsub(pattern=";", replacement="\\,", x=tmp_ids)
      many_ids[["tigrfam"]][gene_num] <- tmp_ids
      next
    }
    if (grepl(pattern="^SQ\\s+SEQUENCE", x=line)) {
      reading_sequence <- TRUE
      tmp_ids <- gsub(pattern="^SQ\\s+SEQUENCE.*AA;\\s+(\\d+)\\s+MW.*$", replacement="\\1", x=line)
      many_ids[["mw"]][gene_num] <- tmp_ids
    }
    if (isTRUE(reading_sequence)) {
      tmp_ids <- gsub(pattern="^\\s+(.*)$", replacement="\\1", x=line)
      many_ids[["aa_sequence"]][gene_num] <- paste0(many_ids[["aa_sequence"]], " ", tmp_ids)
    }
    if (grepl(pattern="^\\/\\/", x=line)) {
      reading_sequence <- FALSE
    }
  } ## End of the for loop
  close(bar)
  message("Finished parsing, creating data frame.")
  uniprot_data <- data.frame()
  uniprot_data <- data.frame(row.names=many_ids[["primary_id"]])
  for (type in id_types) {
    uniprot_data[[type]] <- many_ids[[type]]
  }
  if (!is.null(savefile)) {
    if (savefile != FALSE) {
      saved <- save(list="uniprot_data", file=savefile)
    }
  }
  return(uniprot_data)
}