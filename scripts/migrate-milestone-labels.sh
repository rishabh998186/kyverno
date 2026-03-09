#!/bin/bash

# This script migrates issues and PRs from using milestone labels (e.g., "milestone 1.16.0")
# to using native GitHub Milestones.
# It requires the GitHub CLI (gh) to be authenticated and have appropriate permissions on the repo.

set -euo pipefail

REPO=${1:-"kyverno/kyverno"}

echo "Fetching labels starting with 'milestone ' in $REPO..."

# Get labels matching "milestone "
LABELS=$(gh label list --repo "$REPO" --search "milestone " --limit 100 --json name -q '.[].name')

if [ -z "$LABELS" ]; then
    echo "No milestone labels found."
    exit 0
fi

for LABEL in $LABELS; do
    echo "Processing label: '$LABEL'"
    
    # Extract the targeted milestone name, e.g., '1.16.0'
    MILESTONE_NAME=${LABEL#milestone }
    
    # Ensure milestone exists
    echo "Checking if Milestone '$MILESTONE_NAME' exists..."
    # Check if the milestone exists, if not create it
    MILESTONE_NUMBER=$(gh api repos/"$REPO"/milestones -q ".[] | select(.title==\"$MILESTONE_NAME\") | .number")
    
    if [ -z "$MILESTONE_NUMBER" ]; then
        echo "Milestone '$MILESTONE_NAME' does not exist. Creating it now..."
        MILESTONE_NUMBER=$(gh api -X POST repos/"$REPO"/milestones -f title="$MILESTONE_NAME" -q ".number")
        echo "Created Milestone '$MILESTONE_NAME' with number $MILESTONE_NUMBER"
    else
        echo "Milestone '$MILESTONE_NAME' already exists (number $MILESTONE_NUMBER)"
    fi
    
    # Find all open and closed issues/prs with this label
    echo "Finding issues/PRs with label '$LABEL'..."
    ITEMS=$(gh issue list --repo "$REPO" --state all --label "$LABEL" --limit 1000 --json number -q '.[].number')
    
    if [ -z "$ITEMS" ]; then
        echo "  No existing issues or PRs found with label '$LABEL'"
    else
        for ITEM in $ITEMS; do
            # Note: If an issue/PR has multiple milestone labels, gh issue edit will 
            # simply overwrite the milestone with the one currently being processed.
            # This is generally the desired behavior.
            echo "  Updating issue/PR #$ITEM: adding milestone '$MILESTONE_NAME' and removing label '$LABEL'"
            gh issue edit "$ITEM" --repo "$REPO" --milestone "$MILESTONE_NAME" --remove-label "$LABEL" || echo "  Warning: Failed to update #$ITEM"
        done
    fi

    echo "Deleting label '$LABEL' from repository..."
    gh label delete "$LABEL" --repo "$REPO" --yes || echo "Warning: Failed to delete label '$LABEL'"

    echo "---------------------------------------------------"
done

echo "Milestone migration completed successfully."
