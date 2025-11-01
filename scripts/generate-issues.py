#!/usr/bin/env python3
"""
Generate GitHub issues from ROADMAP.md

Usage:
    python scripts/generate-issues.py --dry-run  # Preview issues
    python scripts/generate-issues.py --create   # Create issues (requires gh CLI)
"""

import re
import sys
import subprocess
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class Task:
    id: str
    phase: str
    title: str
    description: str
    acceptance_criteria: List[str]
    dependencies: List[str]
    labels: List[str]
    effort_hours: int
    files: List[str]
    test_first: List[str]


def parse_roadmap(roadmap_path: str) -> List[Task]:
    """Parse ROADMAP.md and extract tasks"""
    tasks = []
    
    with open(roadmap_path, 'r') as f:
        content = f.read()
    
    # Split by task headers
    task_pattern = r'### (TASK-\d+): (.+?)\n\n(.*?)(?=### TASK-|\Z)'
    matches = re.finditer(task_pattern, content, re.DOTALL)
    
    for match in matches:
        task_id = match.group(1)
        title = match.group(2)
        body = match.group(3)
        
        # Extract phase
        phase_match = re.search(r'\*\*Goal:\*\* (.+)', content[:match.start()])
        phase = phase_match.group(1) if phase_match else "Unknown"
        
        # Extract description
        desc_match = re.search(r'\*\*Description:\*\* (.+)', body)
        description = desc_match.group(1) if desc_match else ""
        
        # Extract acceptance criteria
        ac_section = re.search(r'\*\*Acceptance Criteria:\*\*\n((?:- \[[ x]\] .+\n?)+)', body)
        acceptance_criteria = []
        if ac_section:
            acceptance_criteria = [
                line.strip()[6:].strip()  # Remove "- [ ] "
                for line in ac_section.group(1).strip().split('\n')
                if line.strip()
            ]
        
        # Extract test-first requirements
        tf_section = re.search(r'\*\*Test-First Requirements:\*\*\n((?:- \[[ x]\] .+\n?)+)', body)
        test_first = []
        if tf_section:
            test_first = [
                line.strip()[6:].strip()
                for line in tf_section.group(1).strip().split('\n')
                if line.strip()
            ]
        
        # Extract dependencies
        deps_match = re.search(r'\*\*Dependencies:\*\* (.+)', body)
        dependencies = []
        if deps_match:
            dep_text = deps_match.group(1)
            if dep_text != "None":
                dependencies = [d.strip() for d in dep_text.split(',')]
        
        # Extract labels
        labels_match = re.search(r'\*\*Labels:\*\* (.+)', body)
        labels = []
        if labels_match:
            labels = [l.strip().strip('`') for l in labels_match.group(1).split(',')]
        
        # Extract effort
        effort_match = re.search(r'\*\*Estimated Effort:\*\* (\d+) hours', body)
        effort_hours = int(effort_match.group(1)) if effort_match else 0
        
        # Extract files
        files_section = re.search(r'\*\*Files:\*\*\n```\n((?:.+\n?)+?)```', body)
        files = []
        if files_section:
            files = [
                line.strip()
                for line in files_section.group(1).strip().split('\n')
                if line.strip()
            ]
        
        tasks.append(Task(
            id=task_id,
            phase=phase,
            title=title,
            description=description,
            acceptance_criteria=acceptance_criteria,
            dependencies=dependencies,
            labels=labels,
            effort_hours=effort_hours,
            files=files,
            test_first=test_first
        ))
    
    return tasks


def format_issue_body(task: Task) -> str:
    """Format task as GitHub issue body"""
    body = f"## Description\n\n{task.description}\n\n"
    
    body += f"## Phase\n\n{task.phase}\n\n"
    
    if task.test_first:
        body += "## Test-First Requirements\n\n"
        body += "> ⚠️ **Write tests BEFORE implementation**\n\n"
        for req in task.test_first:
            body += f"- [ ] {req}\n"
        body += "\n"
    
    body += "## Acceptance Criteria\n\n"
    for criterion in task.acceptance_criteria:
        body += f"- [ ] {criterion}\n"
    body += "\n"
    
    if task.dependencies:
        body += "## Dependencies\n\n"
        for dep in task.dependencies:
            body += f"- {dep}\n"
        body += "\n"
    
    if task.files:
        body += "## Files to Create/Modify\n\n"
        body += "```\n"
        for file in task.files:
            body += f"{file}\n"
        body += "```\n\n"
    
    body += f"## Estimated Effort\n\n{task.effort_hours} hours\n\n"
    
    body += "---\n\n"
    body += "**Tiger Style Requirements:**\n"
    body += "- [ ] Minimum 2 assertions per function\n"
    body += "- [ ] All loops are bounded\n"
    body += "- [ ] Explicit error handling (no silent failures)\n"
    body += "- [ ] Code formatted with `zig fmt`\n"
    body += "- [ ] Pre-commit hook passes\n"
    body += "- [ ] All tests pass\n"
    
    return body


def create_github_issue(task: Task, dry_run: bool = True):
    """Create GitHub issue using gh CLI"""
    title = f"{task.id}: {task.title}"
    body = format_issue_body(task)
    
    labels = task.labels + ["tiger-style"]
    
    if dry_run:
        print(f"\n{'='*80}")
        print(f"ISSUE: {title}")
        print(f"Labels: {', '.join(labels)}")
        print(f"{'='*80}")
        print(body)
    else:
        # Use gh CLI to create issue
        cmd = [
            "gh", "issue", "create",
            "--title", title,
            "--body", body,
            "--label", ",".join(labels)
        ]
        
        try:
            subprocess.run(cmd, check=True)
            print(f"✓ Created: {title}")
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to create {title}: {e}", file=sys.stderr)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Generate GitHub issues from roadmap")
    parser.add_argument("--dry-run", action="store_true", help="Preview issues without creating")
    parser.add_argument("--create", action="store_true", help="Create issues on GitHub")
    parser.add_argument("--roadmap", default="ROADMAP.md", help="Path to roadmap file")
    parser.add_argument("--filter", help="Filter tasks by ID pattern (e.g., 'TASK-0' for Phase 0)")
    
    args = parser.parse_args()
    
    if not args.dry_run and not args.create:
        parser.error("Must specify either --dry-run or --create")
    
    tasks = parse_roadmap(args.roadmap)
    
    if args.filter:
        tasks = [t for t in tasks if args.filter in t.id]
    
    print(f"Found {len(tasks)} tasks")
    
    if args.create:
        # Check if gh CLI is available
        try:
            subprocess.run(["gh", "--version"], check=True, capture_output=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("Error: gh CLI not found. Install from https://cli.github.com/", file=sys.stderr)
            sys.exit(1)
        
        response = input(f"Create {len(tasks)} issues on GitHub? (yes/no): ")
        if response.lower() != "yes":
            print("Aborted")
            return
    
    for task in tasks:
        create_github_issue(task, dry_run=args.dry_run)
    
    print(f"\n{'='*80}")
    print(f"Total: {len(tasks)} tasks, {sum(t.effort_hours for t in tasks)} hours")


if __name__ == "__main__":
    main()
