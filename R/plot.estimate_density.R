#' @importFrom insight clean_parameters
#' @export
data_plot.estimate_density <- function(x, data = NULL, centrality = "median", ci = 0.95, ...) {
  dataplot <- x

  if (!"Parameter" %in% names(dataplot)) {
    dataplot$Parameter <- "Distribution"
  }

  # add component and effects columns
  if (!is.null(data)) {
    dataplot <- merge(dataplot, insight::clean_parameters(data), by = "Parameter")
  }

  dataplot <- .fix_facet_names(dataplot)

  dataplot$Parameter <- factor(dataplot$Parameter)
  dataplot$Parameter <- factor(dataplot$Parameter, levels = rev(levels(dataplot$Parameter)))

  # summary
  split_columns <- intersect(c("Parameter", "Effects", "Component"), colnames(dataplot))
  datasplit <- split(dataplot, dataplot[split_columns])
  summary <- do.call(rbind, .compact_list(lapply(datasplit, function(i) {
    if (length(i$x) > 0) {
      Estimate <- as.numeric(bayestestR::point_estimate(i$x, centrality = centrality))
      CI <- as.numeric(bayestestR::ci(i$x, ci = ci))
      out <- data.frame(
        Parameter = unique(i$Parameter),
        x = Estimate,
        CI_low = CI[2],
        CI_high = CI[3],
        stringsAsFactors = FALSE
      )
      if ("Effects" %in% colnames(i)) {
        out$Effects <- unique(i$Effects)
      }
      if ("Component" %in% colnames(i)) {
        out$Component <- unique(i$Component)
      }
    } else {
      out <- NULL
    }
    out
  })))

  summary$Parameter <- factor(summary$Parameter)
  summary$Parameter <- factor(summary$Parameter, levels = levels(dataplot$Parameter))

  attr(dataplot, "summary") <- summary
  attr(dataplot, "info") <- list("xlab" = "Values",
                                 "ylab" = "Density",
                                 "legend_fill" = "Parameter",
                                 "legend_color" = "Parameter",
                                 "title" = "Estimated Density Function")

  class(dataplot) <- c("data_plot", "see_estimate_density", class(dataplot))
  dataplot
}




# Plot --------------------------------------------------------------------

#' Plot method for density estimation of posterior samples
#'
#' The \code{plot()} method for the \code{bayestestR::estimate_density()} function.
#'
#' @param stack Logical, if \code{TRUE}, densities are plotted as stacked lines. Else, densities are plotted for each parameter among each other.
#' @param priors Logical, if \code{TRUE}, prior distributions are simulated (using \code{\link[bayestestR:simulate_prior]{simulate_prior()}}) and added to the plot.
#' @param priors_alpha Alpha value of the prior distributions.
#' @param posteriors_alpha Alpha value of the posterior distributions.
#' @param centrality The point-estimate (centrality index) to compute. May be \code{"median"}, \code{"mean"} or \code{"MAP"}.
#' @param ci Value of probability of the CI (between 0 and 1) to be estimated. Default to .95.
#' @inheritParams data_plot
#' @inheritParams plot.see_bayesfactor_parameters
#' @inheritParams plot.see_cluster_analysis
#' @inheritParams plot.see_check_normality
#'
#' @return A ggplot2-object.
#'
#' @examples
#' \donttest{
#' if (require("bayestestR") && require("rstanarm")) {
#'   set.seed(123)
#'   m <<- stan_glm(Sepal.Length ~ Petal.Width * Species, data = iris, refresh = 0)
#'   result <- estimate_density(m)
#'   plot(result)
#' }
#' }
#' @importFrom rlang .data
#' @importFrom ggridges geom_ridgeline
#' @export
plot.see_estimate_density <- function(x, stack = TRUE, show_intercept = FALSE, n_columns = 1, priors = FALSE, priors_alpha = .4, posteriors_alpha = 0.7, size_line = .9, size_point = 2, centrality = "median", ci = 0.95, ...) {
  # save model for later use
  model <- tryCatch(
    {
      .retrieve_data(x)
    },
    error = function(e) {
      priors <- FALSE
      NULL
    }
  )


  if (!"data_plot" %in% class(x)) {
    x <- data_plot(x, data = model, centrality = centrality, ci = ci, ...)
  }

  if ((!"Effects" %in% names(x) || length(unique(x$Effects)) <= 1) &&
      (!"Component" %in% names(x) || length(unique(x$Component)) <= 1)) n_columns <- NULL

  # get labels
  labels <- .clean_parameter_names(x$Parameter, grid = !is.null(n_columns))

  # remove intercept from output, if requested
  x <- .remove_intercept(x, show_intercept = show_intercept)

  if (stack == TRUE) {
    p <- ggplot(x, aes(x = .data$x, y = .data$y, color = .data$Parameter)) +
      geom_line(size = size_line) +
      add_plot_attributes(x) +
      scale_color_flat(labels = labels)
  } else {
    p <- ggplot(x, aes(x = .data$x, y = .data$Parameter, height = .data$y))

    # add prior layer
    if (priors) {
      p <- p +
        .add_prior_layer_ridgeline(
          model,
          show_intercept = show_intercept,
          priors_alpha = priors_alpha,
          show_ridge_line = FALSE
        ) +
        ggridges::geom_ridgeline(aes(fill = "Posterior"), alpha = posteriors_alpha, color = NA) +
        guides(color = "none") +
        scale_fill_flat(reverse = TRUE) +
        scale_colour_flat(reverse = TRUE)
    } else {
      p <- p +
        ggridges::geom_ridgeline(aes(fill = "Posterior"), alpha = posteriors_alpha, color = NA) +
        guides(fill = "none", color = "none") +
        scale_fill_manual(values = unname(social_colors("grey"))) +
        scale_color_manual(values = unname(social_colors("grey")))
    }

    summary <- attributes(x)$summary
    summary <- .remove_intercept(summary, show_intercept = show_intercept)
    summary$y <- NA

    p <- p +
      geom_errorbarh(data = summary, mapping = aes(xmin = .data$CI_low, xmax = .data$CI_high, color = "Posterior"), size = size_line) +
      geom_point(data = summary, mapping = aes(x = .data$x, color = "Posterior"), size = size_point, fill = "white", shape = 21)

    p <- p + add_plot_attributes(x)
  }


  if (length(unique(x$Parameter)) == 1 || isTRUE(stack)) {
    p <- p + scale_y_continuous(breaks = NULL, labels = NULL)
  } else {
    p <- p + scale_y_discrete(labels = labels)
  }


  if (length(unique(x$Parameter)) == 1) {
    p <- p + guides(color = FALSE)
  }


  if (!is.null(n_columns)) {
    if ("Component" %in% names(x) && "Effects" %in% names(x)) {
      p <- p + facet_wrap(~ Effects + Component, scales = "free", ncol = n_columns)
    } else if ("Effects" %in% names(x)) {
      p <- p + facet_wrap(~ Effects, scales = "free", ncol = n_columns)
    } else if ("Component" %in% names(x)) {
      p <- p + facet_wrap(~ Component, scales = "free", ncol = n_columns)
    }
  }

  p
}




# Density df --------------------------------------------------------------------

#' @export
data_plot.estimate_density_df <- data_plot.estimate_density


#' @importFrom rlang .data
#' @importFrom ggridges geom_ridgeline
#' @importFrom stats setNames
#' @export
plot.see_estimate_density_df <- function(x, stack = TRUE, n_columns = 1, size_line = .9, ...) {
  x$Parameter <- factor(x$Parameter, levels = rev(unique(x$Parameter)))
  labels <- stats::setNames(levels(x$Parameter), levels(x$Parameter))

  if (stack == TRUE) {
    p <- ggplot(x, aes(x = .data$x, y = .data$y, color = .data$Parameter)) +
      geom_line(size = size_line)
  } else {
    p <- ggplot(x, aes(x = .data$x, y = .data$Parameter, height = .data$y)) +
      ggridges::geom_ridgeline()
  }


  if (length(unique(x$Parameter)) == 1 || isTRUE(stack)) {
    p <- p + scale_y_continuous(breaks = NULL, labels = NULL)
  } else {
    p <- p + scale_y_discrete(labels = labels)
  }


  if (length(unique(x$Parameter)) == 1) {
    p <- p + guides(color = FALSE)
  }


  if ("Group" %in% names(x)) {
    p <- p + facet_wrap(~ Group, scales = "free", ncol = n_columns)
  }

  p
}

