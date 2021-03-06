% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/io.R
\name{read.Alteryx2}
\alias{read.Alteryx2}
\title{Alteryx Read Function}
\usage{
read.Alteryx2(name, mode = "data.frame", bIncludeRowNames = FALSE, default)
}
\arguments{
\item{name}{name}

\item{mode}{mode}

\item{bIncludeRowNames}{include row names}

\item{default}{default}
}
\description{
This function reads data from an Alteryx input stream. Every time a
macro/workflow runs this function, the input data gets saved as an rds file
with the prefix ".input", to the macro/workflow directory. This allows the R
code to be run outside of Alteryx.
}

