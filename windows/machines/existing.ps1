# windows/machines/existing.ps1 -- an OLDER machine that should pick up the
# shared defaults without being renamed, re-wallpapered or given new apps.
# Brendan, 2026-10-06: "we also may update old machines with some of this code".
#
#   ... setup.ps1 ... -Machine existing                    # all defaults below
#   ... setup.ps1 ... -Machine existing -Only preferences  # just one piece
#
# Add more pieces here only if they install nothing an old machine wouldn't want.
$MachineConfig = @{
    ComputerName = $null
    # Off for an old machine: we are not weakening a box we may not know well.
    ClaudeSkipPermissions = $false
    Modules      = @("preferences", "claude")
}
