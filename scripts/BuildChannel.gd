extends Reference

# Which kind of build this is:
# - "stable": released from the main branch, talks to savia.nysr.host
# - "test": built from the test branch, talks to the test server and updates
#   from test builds (GitHub pre-releases)
# The release workflow writes "test" here (and the test server's address into
# the scripts) when it builds the test branch. Never change it by hand.
const CHANNEL := "stable"
