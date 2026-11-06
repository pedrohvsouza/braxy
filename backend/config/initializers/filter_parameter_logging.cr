# Filter sensitive request parameters from logs.
#
# Saci filters password, password_confirmation, token and secret by
# default (substring match, case-insensitive). Add app-specific keys
# by uncommenting the line below:
#
#   Saci.filter_parameters = Saci.filter_parameters + ["ssn", "credit_card"]
#
# Keep this file comment-only unless the API above exists in your Saci
# version; initializers are loaded by a require glob from the boot file.
