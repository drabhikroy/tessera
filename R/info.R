# info.R
# The application constants: name, tagline, and version.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
#
# These live here rather than at the top of app.R because of how Shiny
# loads things. Shiny sources app.R into an environment of its own,
# while source() called from inside app.R loads into the global
# environment. A function defined in R/ is closed over the global
# environment, so it cannot see a value assigned at the top of app.R.
#
# Keeping the constants in a sourced file puts them in the same
# environment as the functions that read them. Anything shared between
# app.R and a file in R/ belongs here for the same reason.

APP_NAME    <- "Tessera"
APP_TAG     <- "From relationships to structure."
APP_VERSION <- "0.25.0"
