#' Retrieve details of a Quantarctica data set
#'
#' @param name string: the name of the data set
#' @param refresh_cache logical: as for \code{qa_get}
#' @param verbose logical: show progress messages?
#'
#' @return A tibble
#'
#' @export
qa_dataset <- function(name, refresh_cache = FALSE, verbose = FALSE) {
    ## find name in datasets index
    lx <- dataset_index(refresh_cache = FALSE, verbose = FALSE, expand_source = FALSE)
    idx <- lx$name == name
    if (sum(idx) < 1) {
        ## try case-insensitive
        idx <- tolower(lx$name) == tolower(name)
    }
    if (sum(idx) < 1) {
        stop("no matching data set found")
    } else if (sum(idx) > 1) {
        stop("multiple matching data sets found")
    } else {
        path <- dirname(lx$source[idx])
    }
    out <- bb_source(name = name,
                     id = paste0("Quantarctica: ", name),
                     description = "Quantarctica data",
                     doc_url = "http://quantarctica.npolar.no/",
                     citation = paste0("Matsuoka, K., Skoglund, A., & Roth, G. (2018). Quantarctica ", name, ". Norwegian Polar Institute. https://doi.org/10.21334/npolar.2018.8516e961"),
                     source_url = sub("[/\\]+$", "/", paste0(qa_mirror(), path, "/")), ## ensure trailing sep
                     license = "CC-BY 4.0 International",
                     method = list("bb_handler_rget", level = 2, no_host = TRUE, cut_dirs = 1, accept_download_extra = "(cpg|dbf|prj|qix|shp|shx)$"),
                     ## no_host = TRUE and cut_dirs = 1 so that we drop the hostname/Quantarctica3 part of the directory
                     postprocess = NULL##list("bb_unzip")##,
                     ##collection_size = 0.6,
                     ##data_group = "Topography")
                     )
    ## add the path to the main file of this data set
    out$main_file <- lx$source[idx] ## relative to cache dir root
    out
}


#' Available Quantarctica data sets
#'
#' @param refresh_cache logical: as for \code{qa_get}
#' @param verbose logical: show progress messages?
#'
#' @return A tibble with columns \code{id}, \code{name}, \code{source}, and \code{cached}
#'
#' @seealso \code{\link{qa_get}}
#'
#' @examples
#'
#' qa_datasets()
#'
#' @export
qa_datasets <- function(refresh_cache = FALSE, verbose = FALSE) {
    lxs <- dataset_index(refresh_cache = refresh_cache, verbose = verbose, expand_source = TRUE)
    if (!is.null(lxs)) {
        lxs$cached <- vapply(lxs$source, file.exists, FUN.VALUE = TRUE, USE.NAMES = FALSE)
        lxs
    } else {
        warning("something went wrong")
        NULL
    }
}

## internal function to get dataset index
dataset_index <- function(refresh_cache = FALSE, verbose = FALSE, expand_source = TRUE) {
    cache_directory <- qa_cache_dir()
    index_file <- fetch_dataset_index(refresh_cache = refresh_cache, verbose = verbose)
    lxs <- dataset_qgs_to_tibble(index_file)
    if (expand_source) lxs$source <- file.path(cache_directory, lxs$source)
    lxs
}

fetch_dataset_index <- function(refresh_cache = FALSE, verbose = FALSE) {
    cache_directory <- qa_cache_dir()
    index_file <- file.path(cache_directory, "Quantarctica3.qgs")
    if (file.exists(index_file) && !refresh_cache) return(index_file) ## don't re-fetch if not needed
    if (!dir.exists(dirname(index_file))) tryCatch(dir.create(dirname(index_file), recursive = TRUE), error = function(e) stop("Could not create cache_directory: ", dirname(index_file)))
    res <- bb_rget(url = paste0(qa_mirror(), "Quantarctica3.qgs"), force_local_filename = index_file, use_url_directory = FALSE, verbose = verbose)
    if (file.exists(index_file)) {
        index_file
    } else {
        stop("could not retrieve dataset index file")
    }
}

## internal function to turn Quantarctica3.qgs file into tibble
dataset_qgs_to_tibble <- function(index_file) {
        lx <- xml2::read_xml(index_file)
        get_layer_details <- function(z) as.data.frame(as.list(xml2::xml_attrs(z))[c("name", "source")], stringsAsFactors = FALSE)
        lxs <- as_tibble(do.call(rbind, lapply(xml2::xml_find_all(lx, ".//layer-tree-layer"), get_layer_details)))
        lxs$source <- sub("^.*Quantarctica3/", "", lxs$source)

        ## clean bad sources
        for (i in seq_along(lxs$source)) {
            if (!grepl("\\.[a-z0-9]$", lxs$source[i])) {
                lxs$source[i] <- strsplit(lxs$source[i], "\\|")[[1]][1]
            }
        }
        ## TODO: add in extra information from elsewhere in the qgs file
        ## e.g. mlx <- xml2::xml_find_all(lx, ".//maplayer")
        ## then see layername and abstract components of each maplayer
        ## and possibly even the colour map (which I think is buried in the "pipe" component):
        ## xml2::xml_find_all(lx, ".//maplayer")[[150]] %>% xml_child("pipe") %>% xml_child("rasterrenderer") %>% xml_child("rastershader") %>% xml_child("colorrampshader")
        lxs
}
