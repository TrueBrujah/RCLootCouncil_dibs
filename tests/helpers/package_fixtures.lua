local M = {}
M.invalidPrefix = "not-a-dibs-package"
M.emptyPackage = "DIBS-PKG-1|{}"
M.truncatedPackage = "DIBS-PKG-1|{[\"packageVersion\"]=1"
M.futureSchema = "DIBS-PKG-1|{[\"packageVersion\"]=1,[\"schemaVersion\"]=999}"
return M
