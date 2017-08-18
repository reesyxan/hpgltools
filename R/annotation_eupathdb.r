#' @export
print_eupath_species <- function() {
  metadata <- download_eupathdb_metadata()
  return(metadata[["Species"]])
}

#' Create an organismDbi instance for an eupathdb organism.
#'
#' @param species  A species in the eupathDb metadata.
#' @param dir  Directory in which to build the packages.
#' @return  The result of attempting to install the organismDbi package.
#' @author  Keith Hughitt
#' @export
make_eupath_organismdbi <- function(species="Leishmania major strain Friedlin", dir=".",
                                    overwrite=FALSE, kegg_abbreviation=NULL,
                                    db_version=NULL, parallel=TRUE) {
    metadata <- download_eupathdb_metadata(db_version=db_version)
    all_species <- metadata[["Species"]]
    entry <- NULL
    grep_hits <- grepl(species, all_species)
    grepped_hits <- all_species[grep_hits]
    if (species %in% all_species) {
        entry <- metadata[metadata[["Species"]] == species, ]
        message(paste0("Yay, found: ", entry[["Species"]]))
    } else if (sum(grep_hits > 0)) {
        species <- grepped_hits[[1]]
        entry <- metadata[metadata[["Species"]] == species, ]
        message("Found the following hits: ", toString(grepped_hits), ", choosing the first.")
    } else {
        stop("Did not find your species.")
    }

    taxa <- make_taxon_names(entry)
    pkgname <- paste0(taxa[["taxon"]], ".v", entry[["SourceVersion"]])
    inst <- as.data.frame(installed.packages())
    if (pkgname %in% inst[["Package"]]) {
        if (isTRUE(overwrite)) {
            message(paste0(pkgname, " is already installed, overwriting it."))
        } else {
            message(paste0(pkgname, " is already installed, set overwrite=TRUE if you wish to reinstall."))
            return(pkgname)
        }
    }
    
    orgdb_name <- make_eupath_orgdb(entry, dir=dir,
                                    kegg_abbreviation=kegg_abbreviation,
                                    parallel=parallel)
    txdb_name <- make_eupath_txdb(entry, dir=dir)

    version <- paste0(entry[["SourceVersion"]], ".0")
    graph_data <- list(
        "join1" = c(GO.db="GOID", orgdb="GO_ID"),
        "join2" = c(orgdb="GID",  txdb="GENEID")
    )

    names(graph_data[["join1"]]) = c("GO.db", orgdb_name)
    names(graph_data[["join2"]]) = c(orgdb_name, txdb_name)

    tt <- sm(requireNamespace(orgdb_name))
    tt <- sm(requireNamespace(txdb_name))
    libstring <- paste0("library(", orgdb_name, ")")
    eval(parse(text=libstring))
    libstring <- paste0("library(", txdb_name, ")")
    eval(parse(text=libstring))
    organism <- taxa[["taxon"]]
    requireNamespace("OrganismDbi")


    author <- as.character(entry[["Maintainer"]])
    maintainer <- as.character(entry[["Maintainer"]])

    destination <- file.path(dir, paste0(sample(c(0:9, letters), 10, replace=TRUE), collapse=""))
    if (file.exists(destination)) {
        unlink(x=destination, recursive=TRUE)
    }
    dir.create(destination, recursive=TRUE)
    version <- format(as.numeric(version), nsmall=1)
    organdb <- sm(OrganismDbi::makeOrganismPackage(
        pkgname = pkgname,
        graphData = graph_data,
        organism = organism,
        version = version,
        maintainer = maintainer,
        author = author,
        destDir = destination,
        license = "Artistic-2.0"
    ))
    organdb_path <- paste0(destination, "/", pkgname)
    organdb_path <- clean_pkg(organdb_path)
    if (class(organdb) == "list") {
        inst <- devtools::install(organdb_path)
    }
    ret <- basename(organdb_path)
return(ret)
}

#' Returns metadata for all eupathdb organisms.
#'
#' @return  Dataframe with lots of rows for the various species in eupathdb.
#' @author  Keith Hughitt
#' @export
download_eupathdb_metadata <- function(db_version=NULL) {
    ## Get EuPathDB version (same for all databases)
    if (is.null(db_version)) {
        db_version <- readLines("http://tritrypdb.org/common/downloads/Current_Release/Build_number")
    } else {
        message("I am reasonably certain that the webservices API does not allow one to change the db version.")
        message("Thus, this argument appears useless, but I will look more into it.")
    }

    shared_tags <- c("Annotation", "EuPathDB", "Eukaryote", "Pathogen", "Parasite")
    tags <- list(
        "AmoebaDB" = c(shared_tags, "Amoeba"),
        "CryptoDB" = c(shared_tags, "Cryptosporidium"),
        "FungiDB" = c(shared_tags, "Fungus", "Fungi"),
        "GiardiaDB" = c(shared_tags, "Giardia"),
        "MicrosporidiaDB" = c(shared_tags, "Microsporidia"),
        "PiroplasmaDB" = c(shared_tags, "Piroplasma"),
        "PlasmoDB" = c(shared_tags, "Plasmodium"),
        "ToxoDB" = c(shared_tags, "Toxoplasmosis"),
        "TrichDB" = c(shared_tags, "Trichomonas"),
        "TriTrypDB" = c(shared_tags, "Trypanosome", "Kinetoplastid", "Leishmania"))
    tag_strings <- lapply(tags, function(x) { paste(x, collapse=",") })

    ## construct API request URL
    base_url <- "http://eupathdb.org/eupathdb/webservices/"
    query_string <- "OrganismQuestions/GenomeDataTypes.json?o-fields=all"
    request_url <- paste0(base_url, query_string)

    ## retrieve organism metadata from EuPathDB
    result <- jsonlite::fromJSON(request_url)
    records <- result[["response"]][["recordset"]][["records"]]

    ## convert to a dataframe
    dat <- data.frame(t(sapply(records[["fields"]], function (x) { x[,"value"] } )),
                      stringsAsFactors=FALSE)
    colnames(dat) <- records[["fields"]][[1]][["name"]]

    ## shared metadata
    ## I wish I were this confident with %>% and transmute, I always get confused by them
    shared_metadata <- dat %>% dplyr::transmute(
                                   BiocVersion=as.character(BiocInstaller::biocVersion()),
                                   Genome=sub(".gff", "", basename(URLgff)),
                                   NumGenes=genecount,
                                   NumOrthologs=orthologcount,
                                   SourceType="GFF",
                                   SourceUrl=URLgff,
                                   SourceVersion=db_version,
                                   Species=organism,
                                   TaxonomyId=ncbi_tax_id,
                                   Coordinate_1_based=TRUE,
                                   DataProvider=project_id,
                                   Maintainer="Keith Hughitt <khughitt@umd.edu>")

    ## Add project-specific tags for each entry
    shared_metadata[["Tags"]] <- sapply(shared_metadata[["DataProvider"]],
                                        function(x) { tag_strings[[x]] })

    ## replace missing taxonomy ids with NAs
    shared_metadata[["TaxonomyId"]][shared_metadata[["TaxonomyId"]] == ''] <- NA

    ## overide missing taxonomy ids for strains where it can be assigned; ideally
    ## OrgDb and GRanges objects should not depend on taxonomy id information since
    ## this precludes the inclusion of a lot of prokaryotic resources.
    known_taxon_ids <- data.frame(
        species=c("Ordospora colligata OC4",
                  "Trypanosoma cruzi CL Brener Esmeraldo-like",
                  "Trypanosoma cruzi CL Brener Non-Esmeraldo-like"),
        taxonomy_id=c("1354746", "353153", "353153"),
        stringsAsFactors=FALSE)

    taxon_mask <- shared_metadata[["Species"]] %in% known_taxon_ids[["species"]]
    ind <- match(shared_metadata[taxon_mask, "Species"], known_taxon_ids[["species"]])
    shared_metadata[taxon_mask,][["TaxonomyId"]] <- as.character(known_taxon_ids[["taxonomy_id"]][ind])

    ## exclude remaining species which are missing taxonomy information from
    ## metadata; cannot construct GRanges/OrgDb instances for them since they are
    ## have no known taxonomy id, and are not in available.species()
    na_ind <- is.na(shared_metadata[["TaxonomyId"]])
    ## I think I will try to hack around this problem.
    ##message(sprintf("- Excluding %d organisms for which no taxonomy id could be assigned (%d remaining)",
    ##                sum(na_ind), sum(!na_ind)))
    ##shared_metadata <- shared_metadata[!na_ind,]

    ## convert remaining taxonomy ids to numeric
    shared_metadata[["TaxonomyId"]] <- as.numeric(shared_metadata[["TaxonomyId"]])

    ## remove any organisms for which no GFF is available
    gff_exists <- sapply(shared_metadata[["SourceUrl"]],
                         function(url) { httr::HEAD(url)[["status_code"]] == 200 })
    ## remove any organisms for which no GFF is available
    ## Once again, I will attempt a workaround, probably via bioconductor.
    ## gff_exists <- sapply(shared_metadata$SourceUrl, function(url) { HEAD(url)$status_code == 200 })
    ##message(sprintf("- Excluding %d organisms for which no GFF file is available (%d remaining)",
    ##                sum(!gff_exists), sum(gff_exists)))
    ##shared_metadata <- shared_metadata[gff_exists,]

    ## generate separate metadata table for OrgDB and GRanges targets
    granges_metadata <- shared_metadata %>%
        dplyr::mutate(
                   Title=sprintf("Transcript information for %s", Species),
                   Description=sprintf("%s %s transcript information for %s", DataProvider, SourceVersion, Species),
                   RDataClass="GRanges",
                   DispatchClass="GRanges",
                   ResourceName=sprintf("GRanges.%s.%s%s.rda", gsub("[ /.]+", "_", Species),
                                        tolower(DataProvider), SourceVersion, "rda")) %>%
        dplyr::mutate(DataPath=file.path("EuPathDB", "GRanges", BiocVersion, ResourceName))
    
    orgdb_metadata <- shared_metadata %>%
        dplyr::mutate(
            Title=sprintf("Genome wide annotations for %s", Species),
            Description=sprintf("%s %s annotations for %s", DataProvider, SourceVersion, Species),
            RDataClass="OrgDb",
            DispatchClass="SQLiteFile",
            ResourceName=sprintf("org.%s.%s.db.sqlite", gsub("[ /.]+", "_", Species),
                                 tolower(substring(DataProvider, 1, nchar(DataProvider) - 2)))
        ) %>%
        dplyr::mutate(RDataPath=file.path("EuPathDB", "OrgDb", BiocVersion, ResourceName))

    return(orgdb_metadata)
}

#' @export
do_eupath_table <- function(type, granges=NULL, provider=NULL, genus_species=NULL,
                            species=NULL, flatten=FALSE, abbreviation=NULL) {
    start_time <- as.POSIXlt(Sys.time())
    message(paste0("Starting collection of the ", type, " data."))
    a_result <- NULL
    if (type == "gff") {
        a_result <- try(get_eupath_gff_table(granges))
    } else if (type == "genes") {
        a_result <- try(get_eupath_gene_types(provider, species))
    } else if (type == "go") {
        a_result <- try(get_eupath_go_term_table(provider, species))
    } else if (type == "pathways") {
        a_result <- try(get_eupath_pathway_table(provider, species))
    } else if (type == "interpro") {
        a_result <- try(get_eupath_interpro_table(provider, species))
    } else if (type == "kegg") {
        a_result <- try(get_kegg_genepaths(species=genus_species,
                                           flatten=flatten,
                                           abbreviation=abbreviation))
    } else if (type == "orthologs") {
        a_result <- try(get_eupath_ortholog_table(provider, species))
    } else {
        message("Do not recognize this table.")
        a_result <- data.frame()
    }
    if (class(a_result) == "try-error") {
        a_result <- data.frame()
    }
    colnames(a_result) <- toupper(colnames(a_result))

    end_time <- as.POSIXlt(Sys.time())
    elapsed_time <- round(x=as.numeric(end_time) - as.numeric(start_time))
    
    retlist <- list("type" = type,
                    "elapsed" = elapsed_time,
                    "result" = a_result)
    return(retlist)
}

#' Generate OrgDb for EuPathDB organism
#' 
#' @param entry One dimensional dataframe with organism metadata
#' @return OrgDb instance
#' @author Keith Hughitt
#' @export
make_eupath_orgdb <- function(entry, dir=".", kegg_abbreviation=NULL,
                              parallel=TRUE) {
    ## Get genus and species from organism name
    taxa <- make_taxon_names(entry)

    ## save gff as tempfile
    input_gff <- tempfile(fileext=".gff")
    downloaded <- sm(download.file(entry[["SourceUrl"]], input_gff,
                                   method="internal", quiet=TRUE))

    ## get chromosome information from GFF file
    gff <- rtracklayer::import.gff3(input_gff)
    
    ## gene/chr mapping
    genes <- gff[gff$type == "gene"]

    chr_mapping <- data.frame(
        "GID" = genes$ID,
        "CHR" = as.character(GenomicRanges::seqnames(genes)),
        stringsAsFactors=FALSE)

    tables <- list(
        "gff" = NULL,
        "genes" = NULL,
        "go" = NULL,
        "pathways" = NULL,
        "interpro" = NULL,
        "kegg" = NULL,
        "orthologs" = NULL)
    res <- NULL
    chosen_provider <- entry[["DataProvider"]]
    chosen_species <- entry[["Species"]]
    if (isTRUE(parallel)) {
        message("Querying the EuPathDb tables in parallel, this takes a while.")
        ## Hard set to the number of tables I am downloading,
        ## This perhaps should be changed.
        tt <- sm(require("parallel"))
        tt <- sm(require("doParallel"))
        tt <- sm(require("iterators"))
        tt <- sm(require("foreach"))
        cl <- parallel::makeCluster(length(tables))
        doParallel::registerDoParallel(cl)
        cl <- parallel::makeCluster(length(tables))
        res <- foreach(c=1:length(names(tables)), .packages=c("hpgltools")) %dopar% {
            type <- names(tables)[c]
            stuff <- do_eupath_table(type,
                                     provider=chosen_provider,
                                     species=chosen_species,
                                     genus_species=taxa[["genus_species"]],
                                     flatten=FALSE,
                                     abbreviation=kegg_abbreviation,
                                     granges=gff)
        } ## End foreach() %dopar% { }
        parallel::stopCluster(cl)
        message("Finished downloading tables, collecting outputs.")
        ## foreach returns the results in no particular order
        ## Therefore, I will reorder the results now and ensure that they are happy.
        for (r in 1:length(tables)) {
            a_result <- res[[r]]
            type <- a_result[["type"]]
            result <- a_result[["result"]]
            tables[[type]] <- result
        }
        rm(res)
    } else {
        results <- list()
        for (c in 1:length(names(tables))) {
            type <- names(tables)[c]
            results[[type]] <- do_eupath_table(type,
                                               provider=chosen_provider,
                                               species=chosen_species,
                                               genus_species=taxa[["genus_species"]],
                                               flatten=FALSE,
                                               abbreviation=kegg_abbreviation,
                                               granges=gff)
            tables[[type]] <- results[[type]][["result"]]
        }
        rm(results)
    }

    ## create a randomly-named sub-directory to store orgdb output in; since
    ## makeOrganismPackage doesn"t incorporate strain information in the
    ## package name, this is necessary to avoid directory name collisions
    build_dir <- file.path(dir, paste0(sample(c(0:9, letters), 10, replace=TRUE), collapse=""))
    created <- dir.create(build_dir, recursive=TRUE)

    ## Compile list of arguments for makeOrgPackage call

    if (nrow(tables[["gff"]]) == 0) {
        message("Something is wrong with the gene_info table.")
        message("Rerunning gene_info generator.")
        tmp <- do_eupath_table("gff", granges=gff)
        tables[["gff"]] <- tmp[["result"]]
        rm(tmp)
    }
    if (nrow(tables[["genes"]]) == 0) {
        message("Something is wrong with the gene types table.")
        message("Rerunning the genes generator.")
        tmp <- do_eupath_table("genes", provider=chosen_provider,
                               species=chosen_species)
        tables[["genes"]] <- tmp[["result"]]
        rm(tmp)
    }

    orgdb_args <- list(
        "gene_info"  = tables[["gff"]],
        "chromosome" = chr_mapping,
        "type" = tables[["genes"]],
        "version" = paste0(entry[["SourceVersion"]], ".0"),
        "author" = entry[["Maintainer"]],
        "maintainer" = entry[["Maintainer"]],
        "tax_id" = as.character(entry[["TaxonomyId"]]),
        "genus" = taxa[["genus"]],
        "species" = paste0(taxa[["species_strain"]], ".v", entry[["SourceVersion"]]),
        "outputDir" = build_dir)
    
    ## add non-empty tables
    if (nrow(tables[["go"]]) > 0) {
        orgdb_args[["go"]] <- tables[["go"]]
    }
    if (nrow(tables[["pathways"]]) > 0) {
        orgdb_args[["pathways"]] <- tables[["pathways"]]
    }
    if (nrow(tables[["interpro"]]) > 0) {
        orgdb_args[["interpro"]] <- tables[["interpro"]]
    }
    if (nrow(tables[["orthologs"]]) > 0) {
        orgdb_args[["orthologs"]] <- tables[["orthologs"]]
    }
    if (nrow(tables[["kegg"]]) > 0) {
        orgdb_args[["kegg"]] <- tables[["kegg"]]
    }

    ## Make sure no duplicated stuff snuck through, or makeOrgPackage throws an error.
    ## Make sure that every GID field is character, too
    ## -- otherwise you get 'The type of data in the 'GID' columns must be the same for all data.frames.'
    for (i in 1:length(orgdb_args)) {
        if (class(orgdb_args[[i]]) == "data.frame") {
            ## First swap out NA to ""
            na_tmp <- orgdb_args[[i]]
            na_set <- is.na(na_tmp)
            na_tmp[na_set] <- ""
            orgdb_args[[i]] <- na_tmp
            ## Then remove duplicated elements.
            orgdb_dups <- duplicated(orgdb_args[[i]])
            if (sum(orgdb_dups) > 0) {
                tmp <- orgdb_args[[i]]
                tmp <- tmp[!orgdb_dups, ]
                orgdb_args[[i]] <- tmp
            }
            ## Finally, make sure all GID columns are characters
            orgdb_args[[i]][["GID"]] <- as.character(orgdb_args[[i]][["GID"]])
        }
    }

    tt <- sm(require("AnnotationForge"))
    message(sprintf("- Calling makeOrgPackage for %s", entry[["Species"]]))
    orgdb_path <- sm(do.call("makeOrgPackage", orgdb_args))

    ## Fix name in sqlite metadata table
    dbpath <- file.path(orgdb_path, "inst/extdata",
                        sub(".db", ".sqlite", basename(orgdb_path)))

    message(sprintf("- Fixing sqlite Orgdb sqlite database %s", dbpath))

    ## make sqlite database editable
    Sys.chmod(dbpath, mode='0644')
    db <- RSQLite::dbConnect(RSQLite::SQLite(), dbname=dbpath)
    ## update SPECIES field
    query <- sprintf('UPDATE metadata SET value="%s" WHERE name="SPECIES";',
                     entry[["Species"]])
    sq_result <- RSQLite::dbSendQuery(conn=db, query)
    ## update ORGANISM field
    query <- sprintf('UPDATE metadata SET value="%s" WHERE name="ORGANISM";',
                     entry[["Species"]])
    sq_result <- RSQLite::dbSendQuery(conn=db, query)
    ## lock it back down
    Sys.chmod(dbpath, mode="0444")

    ## Clean up any strangeness in the DESCRIPTION file
    orgdb_path <- clean_pkg(orgdb_path)
    ## And install the resulting package.
    inst <- sm(try(devtools::install(orgdb_path)))
    if (class(inst) != "try-error") {
        unlink(build_dir, recursive=TRUE)
        message(paste0("Installed ", orgdb_path))
    }
    ## return the path to the sqlite database
    ret <- basename(orgdb_path)
    return(ret)
}

#' Generate TxDb for EuPathDB organism
#' 
#' @param entry  One dimensional dataframe with organism metadata.
#' @param dir  Base directory for building the package.
#' @return TxDb instance
#' @author atb 
make_eupath_txdb <- function(entry, dir=".") {
    taxa <- make_taxon_names(entry)

    ## save gff as tempfile
    input_gff <- tempfile(fileext=".gff")
    tt <- sm(download.file(entry[["SourceUrl"]], input_gff, method="internal", quiet=TRUE))

    chr_entries <- read.delim(file=input_gff, header=FALSE, sep="")
    chromosomes <- chr_entries[["V1"]] == "##sequence-region"
    chromosomes <- chr_entries[chromosomes, c("V2", "V3", "V4")]
    colnames(chromosomes) <- c("ID", "start", "end")
    chromosome_info <- data.frame(
        "chrom" = chromosomes[["ID"]],
        "length" = as.numeric(chromosomes[["end"]]),
        "is_circular" = NA,
        stringsAsFactors=FALSE)

    txdb_metadata <- as.data.frame(t(entry))
    txdb_metadata[["name"]] <- rownames(txdb_metadata)
    colnames(txdb_metadata) <- c("value", "name")
    txdb_metadata <- txdb_metadata[, c("name", "value")]
    txdb <- sm(try(GenomicFeatures::makeTxDbFromGFF(
                                        file=input_gff,
                                        format="gff",
                                        chrominfo=chromosome_info,
                                        dataSource=entry[["SourceUrl"]],
                                        organism=paste0(taxa[["genus"]], " ", taxa[["species"]]),
                                        ## metadata=t(entry))
                                        )))
    if (class(txdb) == "try-error") {
        stop("The txdb creation failed.")
    }

    package_name <- paste0("TxDb.", taxa[["genus"]], ".", taxa[["species_strain"]],
                           ".", entry[["DataProvider"]], ".v", entry[["SourceVersion"]])

    ## This is the section I yanked
    provider <- GenomicFeatures:::.getMetaDataValue(txdb, "Data source")
    providerVersion <- GenomicFeatures:::.getTxDbVersion(txdb)
    dbType <- GenomicFeatures:::.getMetaDataValue(txdb, "Db type")
    authors <- GenomicFeatures:::.normAuthor(entry[["Maintainer"]], entry[["Maintainer"]])
    template_path <- system.file("txdb-template", package = "GenomicFeatures")
    symvals <- list("PKGTITLE" = paste("Annotation package for", dbType, "object(s)"),
                    "PKGDESCRIPTION" = paste("Exposes an annotation databases generated from",
                                             GenomicFeatures:::.getMetaDataValue(txdb, "Data source"),
                                             "by exposing these as", dbType, "objects"),
                    "PKGVERSION" = paste0(entry[["SourceVersion"]], ".0"),
                    "AUTHOR" = paste(authors, collapse = ", "),
                    "MAINTAINER" = as.character(GenomicFeatures:::.getMaintainer(authors)),
                    "GFVERSION" = GenomicFeatures:::.getMetaDataValue(txdb, "GenomicFeatures version at creation time"),
                    "LIC" = "Artistic-2.0",
                    "DBTYPE" = dbType,
                    "ORGANISM" = GenomicFeatures:::.getMetaDataValue(txdb,"Organism"),
                    "SPECIES" = GenomicFeatures:::.getMetaDataValue(txdb, "Organism"),
                    "PROVIDER" = provider,
                    "PROVIDERVERSION" = providerVersion,
                    "RELEASEDATE" = GenomicFeatures:::.getMetaDataValue(txdb, "Creation time"),
                    ## SOURCEURL = GenomicFeatures:::.getMetaDataValue(txdb, "Resource URL"),
                    "SOURCEURL" = entry[["SourceUrl"]],
                    "ORGANISMBIOCVIEW" = gsub(" ", "_", GenomicFeatures:::.getMetaDataValue(txdb, "Organism")),
                    "TXDBOBJNAME" = package_name)
    if (any(duplicated(names(symvals)))) {
        str(symvals)
        stop("'symvals' contains duplicated symbols")
    }
    is_OK <- sapply(symvals, S4Vectors::isSingleString)
    if (!all(is_OK)) {
        bad_syms <- paste(names(is_OK)[!is_OK], collapse=", ")
        stop("values for symbols ", bad_syms, " are not single strings")
    }
    build_dir <- file.path(dir, paste0(sample(c(0:9, letters), 10, replace=TRUE), collapse=""))
    tt <- dir.create(build_dir, recursive=TRUE)

    pkg_list <- sm(Biobase::createPackage(pkgname=package_name,
                                          destinationDir=build_dir,
                                          originDir=template_path,
                                          symbolValues=symvals,
                                          unlink=TRUE))
    db_path <- file.path(build_dir, package_name, "inst", "extdata",
                         paste(package_name, "sqlite", sep="."))
    obj <- try(AnnotationDbi::saveDb(txdb, file=db_path))
    if (class(obj) == "try-error") {
        warning("Failed to save the txdb object.")
    }

    install_dir <- paste0(build_dir, "/", package_name)
    install_dir <- sm(clean_pkg(install_dir))
    result <- sm(try(devtools::install(install_dir)))
    result <- basename(install_dir)
    return(result)
}

make_taxon_names <- function(entry) {
    species_parts <- unlist(strsplit(entry[["Species"]], " "))
    genus <- species_parts[1]
    species <- species_parts[2]

    taxon <- gsub(pattern=" ", replacement=".", x=entry[["Species"]])
    genus <- gsub(pattern=" ", replacement="_", x=genus)
    species <- gsub(pattern=" ", replacement="_", x=species)

    taxon <- gsub(pattern="-", replacement="_", x=taxon)
    genus <- gsub(pattern="-", replacement="_", x=genus)
    species <- gsub(pattern="-", replacement="_", x=species)

    taxon <- gsub(pattern="\\/", replacement="", x=taxon)
    genus <- gsub(pattern="\\/", replacement="", x=genus)
    species <- gsub(pattern="\\/", replacement="", x=species)

    genus <- gsub(pattern="\\.", replacement="_", x=genus)
    species <- gsub(pattern="\\.", replacement="_", x=species)

    taxon <- gsub(pattern="strain_", replacement="", x=taxon)
    species <- gsub(pattern="strain_", replacement="", x=species)

    species_strain <- paste(unlist(strsplit(taxon, "_"))[-1], collapse="")
    genus_species <- paste0(genus, "_", species)

    taxa <- list(
        "genus" = genus,
        "species" = species,
        "taxon" = taxon,
        "species_strain" = species_strain,
        "genus_species" = genus_species)
    return(taxa)
}

#' Extract gene information from a GFF file
#'
#' @param gff GenomicRanges instance as returned by `import.gff3`
#' @param return data.frame containing basic gene information (ID, description,
#' etc.)
#' @author Keith Hughitt
#' @export
get_eupath_gff_table <- function(granges=NULL) {
    ## get gene features and convert to a dataframe
    genes <- granges[granges$type == "gene"]
    gene_info <- as.data.frame(GenomicRanges::elementMetadata(genes))

    ## drop any empty and NA columns
    na_mask <- apply(gene_info, 2, function(x) { sum(!is.na(x)) > 0 })
    empty_mask <- apply(gene_info, 2, function(x) { length(unlist(x)) > 0 })
    gene_info <- gene_info[, na_mask & empty_mask]

    ## remove problematic GENECOLOUR field if it exists.
    ## Found for "Leishmania braziliensis MHOM/BR/75/M2904" -- only one row
    ## has a non-empty value and it does not appear to be correct:
    ## > gene_info$GENECOLOUR[1859]
    ## [[1]]
    ## [1] "10"                  "LbrM15.0470"         "LbrM.15.0630"
    ## "LbrM15_V2.0630"      "LbrM15_V2.0630:pep"  "LbrM15_V2.0630:mRNA"
    gene_info <- gene_info[, colnames(gene_info) != "GENECOLOUR"]

    ## Convert form-encoded description string to human-readable
    gene_info[["description"]] <- gsub("\\+", " ", gene_info[["description"]])

    ## Normalize columns names
    colnames(gene_info) <- toupper(colnames(gene_info))
    colnames(gene_info)[colnames(gene_info) == "ID"] <- "GID"

    ## Move gid to the front of the line.
    gid_index <- grep("GID", colnames(gene_info))
    gene_info <- gene_info[, c(gid_index, (1:ncol(gene_info))[-gid_index])]
    colnames(gene_info) <- paste0("GENE", colnames(gene_info))
    colnames(gene_info)[1] <- "GID"

    ## fix type for GENEALIAS column if present (found in version 28 and
    ## earlier)
    if ("GENEALIAS" %in% colnames(gene_info)) {
        gene_info[["GENEALIAS"]] <- as.character(gene_info[["GENEALIAS"]])

        ## Remove any newlines present in GENEALIAS field;
        ## as.character inserts newlines for objects with >500 characters.
        ## https://stat.ethz.ch/R-manual/R-devel/library/base/html/character.html
        gene_info[["GENEALIAS"]] <- gsub("\n", "", gene_info[["GENEALIAS"]])
    }

    return(gene_info)
}

#' Returns a mapping of gene ID to gene type for a specified organism
#'
#' @param data_provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param organism Full name of organism, as used by EuPathDB APIs
#'
#' @return Dataframe with 'GID' and 'TYPE' columns.
#' @author Keith Hughitt
#' @export
get_eupath_gene_types <- function(data_provider, organism) {
    ## query EuPathDB API
    res <- query_eupathdb(data_provider, organism,
                          list(`o-fields` = "primary_key,gene_type"))
    dat <- res[["response"]][["recordset"]][["records"]]

    ## get vector of types
    ids <- unlist(sapply(dat[["fields"]], function(x) { strsplit(x[, "value"], ",")[1] }))
    types <- unlist(sapply(dat[["fields"]], function(x) { strsplit(x[, "value"], ",")[2] }))

    df <- data.frame("GID" = ids,
                     "TYPE" = types,
                     stringsAsFactors=FALSE)

    ## remove duplicated rows and return
    df[!duplicated(df), ]
    return(df)
}

#' @export
get_eupath_go_term_table <- function(data_provider, organism) {
    ## retrieve GoTerms table
    ## result <- retrieve_eupathdb_table(data_provider, organism, 'GoTerms')
    result <- retrieve_eupathdb_attributes(data_provider, organism, "GOTerms")

    if (nrow(result) == 0) {
        return(result)
    }

    ## convert column names to uppercase for consistency
    colnames(result) <- toupper(colnames(result))

    ## drop uneeded columns
    result <- result[, colnames(result) %in% c("GID", "ONTOLOGY", "GO_ID",
                                               "GO_TERM_NAME", "SOURCE",
                                               "EVIDENCE_CODE")]

    ## remove duplicated entries resulting from alternative sources / envidence
    ## codes
    result <- result[!duplicated(result), ]

    ## remove rows missing the ontology field (Bug in EuPathDB 33; affects only
    ## a small number of entries)
    result <- result[!is.na(result[["ONTOLOGY"]]), ]

    return(result)
}

#' 2017/07/08: IN DEVELOPMENT
#'
#' Returns a mapping of gene ID to metabolic pathways (KEGG, LeishCyc, etc.)
#'
#' @param data_provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param organism Full name of organism, as used by EuPathDB APIs
#'
#' @return Dataframe with gene/pathway mapping
#'
#' @author Keith Hughitt
#' @export
get_eupath_pathway_table <- function(data_provider, organism) {
    ## query body as a structured list
    ##query_body <- list(
    ##    answerSpec=list(
    ##        "questionName" = jsonlite::unbox("GeneQuestions.GenesByTaxonGene"),
    ##        parameters = list(organism = jsonlite::unbox(organism)),
    ##        viewFilters = list(),
    ##        filters = list()
    ##    ),
    ##    formatting = list(
    ##        formatConfig = list(
    ##            tables = "MetabolicPathways",
    ##            includeHeader = jsonlite::unbox("true"),
    ##            attachmentType = jsonlite::unbox("plain")
    ##        ),
    ##        format = jsonlite::unbox("tableTabular")
    ##    ))
    ##
    ## query EuPathDB
    ##res <- read.delim(textConnection(post_eupathdb(data_provider, query_body)), sep="\t")
    ##
    ## if no pathway information is available, return an empty dataframe
    ##if (nrow(res) == 0) {
    ##    return(data.frame())
    ##}
    ## drop empty column
    ## res <- res[, 1:7]
    ## simplify column names
    ## > colnames(res)
    ## [1] "X.Gene.ID."                        "X.pathway_source_id."
    ## [3] "X.Pathway."                        "X.Pathway.Source."
    ## [5] "X.EC.Number.Matched.in.Pathway."   "X.expasy_url."
    ## [7] "X...Reactions.Matching.EC.Number."

    result <- retrieve_eupathdb_attributes(data_provider, organism, "MetabolicPathways")

    colnames(result) <- toupper(sub("_+$", "", sub("^X_+", "", gsub("\\.", "_", colnames(result)))))
    result <- result[!duplicated(result), ]

    return(result)
}

#' Returns a mapping of gene ID to InterPro domains for a specified organism
#'
#' @param data_provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param organism Full name of organism, as used by EuPathDB APIs
#'
#' @return Dataframe with ....
#' @author Keith Hughitt
#' @export
get_eupath_interpro_table <- function(data_provider, organism) {
    ## retrieve InterPro domain table
    result <- retrieve_eupathdb_attributes(data_provider, organism, "InterPro")

    ## fix numeric types
    result[["interpro_e_value"]] <- as.numeric(result[["interpro_e_value"]])
    result[["interpro_start_min"]] <- as.numeric(result[["interpro_start_min"]])
    result[["interpro_end_min"]] <- as.numeric(result[["interpro_end_min"]])

    ## fix column names and return result
    colnames(result) <- toupper(colnames(result))

    ## replace NA"s with empty strings (occur in INTERPRO_FAMILY_ID and
    ## INTERPRO_SECONDARY_ID fields)
    ## result[is.na(result)] <- ""
    for (col in colnames(result)) {
        if (class(result[[col]]) != "numeric") {
            nas <- is.na(result[[col]])
            result[nas, col] <- ""
        }
    }

    return(result)
}

#' Returns a mapping of gene ID to ortholog genes
#'
#' @param data_provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param organism Full name of organism, as used by EuPathDB APIs
#'
#' @return Dataframe with ....
#' @author Keith Hughitt
#' @export
get_eupath_ortholog_table <- function(data_provider, organism, workaround=FALSE) {
    ## retrieve ortholog domain table
    result <- retrieve_eupathdb_attributes(data_provider,
                                           organism, "Orthologs",
                                           workaround=workaround)

    ## fix column names and return result
    colnames(result) <- toupper(colnames(result))

    return(result)
}


#' Queries one of the EuPathDB APIs using a POST request and returns a
#' dataframe representation of the result.
#
#' Note: As of 2017/07/13, POST requests are not yet supported on EuPathDB.
#' Note: 2017/07/13 POST queries can only use the new API
#'
#' @param data_provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param organism Full name of organism, as used by EuPathDB APIs
#' @param query_args String of additional query arguments
#' @param wadl String specifying API service to be queried
#' @param format String specifying API response type (currently only 'json'
#'        is supported)
#' @return list containing response from API request.
#'
#' More information
#' ----------------
#' 1. http://tritrypdb.org/tritrypdb/serviceList.jsp
#' @author Keith Hughitt
post_eupathdb <- function(data_provider, query_body) {
    ## construct API query
    api_uri <- sprintf("http://%s.org/%s/service/answer", tolower(data_provider), tolower(data_provider))
    result <- httr::content(httr::POST(api_uri, body=jsonlite::toJSON(query_body)))
    return(result)
}

#' Queries one of the EuPathDB APIs using a GET request and returns a dataframe
#' representation of the result.
#'
#' @param data_provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param organism Full name of organism, as used by EuPathDB APIs
#' @param query_args String of additional query arguments
#' @param wadl String specifying API service to be queried
#' @param format String specifying API response type (currently only 'json'
#'        is supported)
#' @return list containing response from API request.
#'
#' More information
#' ----------------
#' 1. http://tritrypdb.org/tritrypdb/serviceList.jsp
#'
#' @author Keith Hughitt
query_eupathdb <- function(data_provider, organism, query_args,
                           wadl="GeneQuestions/GenesByTaxon", format="json", workaround=FALSE) {
    ## construct API query
    base_url <- sprintf("http://%s.org/webservices/%s.%s?",
                        tolower(data_provider), wadl, format)

    ## add organism to query arguments
    query_args[["organism"]] <- utils::URLencode(organism, reserved=TRUE)
    query_string <- paste(paste(names(query_args), query_args, sep="="), collapse="&")

    ## GET query
    ## query_string <- sprintf("?organism=%s&%s",
    ##                        , query_args_str)
    request_url <- paste0(base_url, query_string)

    ## logging
    if (nchar(request_url) > 200) {
        log_url <- paste0(strtrim(request_url, 160), "...")
    } else {
        log_url <- request_url
    }
    message(sprintf("- Querying %s", log_url))

    result <- NULL
    ## query API for gene types
    if (isTRUE(workaround)) {
        file <- download.file(url=request_url, destfile="tmpfile.json")
        result <- jsonlite::fromJSON("tmpfile.json")
        file.remove("tmpfile.json")
    } else {
        ## GET query
        result <- jsonlite::fromJSON(request_url)
    }
    return(result)
}

#' Queries one of the EuPathDB APIs for gene data
#'
#' Note that as of version 30, EuPathDB no longer supports table queries for
#' genes, and as such this method must be used instead. Support for tables
#' queries is likely to be returned in future versions of EuPathDB.
#'
#' @param data_provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param organism Full name of organism, as used by EuPathDB APIs
#' @param table_name Name of the particular table to be retrieved (e.g.
#' 'GoTerms')
#' @param wadl String specifying API service to be queried
#' @param format String specifying API response type (currently only 'json'
#'        is supported)
#' @return list containing response from API request.
#' @author Keith Hughitt
retrieve_eupathdb_attributes <- function(data_provider, organism, table_name,
                                         wadl="GeneQuestions/GenesByTaxonGene",
                                         format="json", workaround=FALSE) {
    ## query EuPathDB API
    res <- query_eupathdb(data_provider, organism,
                          list(`o-tables`=table_name,
                               `o-fields`="primary_key"), wadl)
    dat <- res[["response"]][["recordset"]][["records"]]

    message(sprintf("- Parsing %s table for %s.", table_name, organism))

    ## drop genes with no associated table entries
    gene_mask <- sapply(dat[, "tables"], function(x) { length(x[["rows"]][[1]]) > 0})
    dat <- dat[gene_mask, ]

    ## create empty data frame to store result in
    result <- data.frame(stringsAsFactors=FALSE)

    ## if no rows found, return empty data.frame
    if (nrow(dat) == 0) {
        return(result)
    }

    ## fix id field
    dat[["id"]] <- unlist(sapply(dat[["fields"]], function(x) { strsplit(x[, "value"], ",")[1] }))

    message(sprintf("- Parsing %d rows in %s table for %s.", nrow(dat), table_name, organism))

    ## iterate over remaining genes and extract table entries for them
    for (i in 1:nrow(dat)) {
        ## example entry:
        ##
        ## > dat$tables[[1]]$rows[[1]]$fields[[1]]
        ##         name                      value
        ## 1         go_id                 GO:0007018
        ## 2      ontology         Biological Process
        ## 3  go_term_name microtubule-based movement
        ## 4        source                   Interpro
        ## 5 evidence_code                        IEA
        ## 6        is_not                       <NA>
        table_entries <- dat[["tables"]][[i]]
        rows <- t(sapply(table_entries[["rows"]][[1]][["fields"]], function(x) { x[["value"]] }))
        result <- rbind(result, cbind(dat[["id"]][i], rows))

        if (i %% 1000 == 0) {
            message(sprintf(" - Parsing row %d/%d in %s table for %s.",
                            i, nrow(dat), table_name, organism))
        }
    }

    for (col in colnames(result)) {
        if (class(result[[col]]) != "numeric") {
            result[[col]] <- as.character(result[[col]])
        }
    }

    ## set column names for result
    colnames(result) <- c("GID", dat[["tables"]][[1]][["rows"]][[1]][["fields"]][[1]][["name"]])
    return(result)
}

## EOF