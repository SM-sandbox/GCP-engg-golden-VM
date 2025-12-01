#!/usr/bin/env python3
"""
Git Statistics Tracker
Tracks lines of code changes, commits, and repository activity
"""

import os
import sys
import json
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List

# Configuration
DEV_USER = os.getenv('DEV_USER', 'jerry')
PROJECTS_ROOT = os.getenv('PROJECTS_ROOT', f'/home/{DEV_USER}/projects')
GIT_LOG_DIR = os.getenv('GIT_LOG_DIR', '/var/log/dev-git')


def run_git_command(repo_path: str, command: List[str]) -> str:
    """Run a git command in a repository"""
    try:
        result = subprocess.run(
            ['git', '-C', repo_path] + command,
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.stdout.strip()
    except Exception as e:
        print(f"Error running git command in {repo_path}: {e}", file=sys.stderr)
        return ""


def get_repository_stats(repo_path: str) -> Dict:
    """Get comprehensive stats for a single repository"""
    repo_name = os.path.basename(repo_path)
    
    stats = {
        'repository': repo_name,
        'path': repo_path,
        'timestamp': datetime.utcnow().isoformat(),
    }
    
    # Check if it's a git repo
    if not os.path.exists(os.path.join(repo_path, '.git')):
        stats['error'] = 'Not a git repository'
        return stats
    
    # Get current branch
    current_branch = run_git_command(repo_path, ['rev-parse', '--abbrev-ref', 'HEAD'])
    stats['current_branch'] = current_branch
    
    # Get commit count
    commit_count = run_git_command(repo_path, ['rev-list', '--count', 'HEAD'])
    stats['total_commits'] = int(commit_count) if commit_count.isdigit() else 0
    
    # Get commits in last 24 hours
    since_time = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d %H:%M:%S')
    recent_commits = run_git_command(repo_path, ['log', '--since', since_time, '--oneline'])
    stats['commits_last_24h'] = len(recent_commits.split('\n')) if recent_commits else 0
    
    # Get LOC stats (additions/deletions in last 24 hours)
    loc_stats = run_git_command(repo_path, ['diff', '--shortstat', f'@{{1 day ago}}..HEAD'])
    stats['loc_changes_24h'] = parse_diff_stat(loc_stats)
    
    # Get file change count (last 24 hours)
    changed_files = run_git_command(repo_path, ['diff', '--name-only', f'@{{1 day ago}}..HEAD'])
    stats['files_changed_24h'] = len(changed_files.split('\n')) if changed_files else 0
    
    # Get unstaged changes
    unstaged = run_git_command(repo_path, ['diff', '--name-only'])
    stats['unstaged_files'] = len(unstaged.split('\n')) if unstaged else 0
    
    # Get staged changes
    staged = run_git_command(repo_path, ['diff', '--cached', '--name-only'])
    stats['staged_files'] = len(staged.split('\n')) if staged else 0
    
    # Get untracked files
    untracked = run_git_command(repo_path, ['ls-files', '--others', '--exclude-standard'])
    stats['untracked_files'] = len(untracked.split('\n')) if untracked else 0
    
    # Get last commit info
    last_commit_info = run_git_command(repo_path, ['log', '-1', '--format=%H|%an|%ae|%ai|%s'])
    if last_commit_info:
        parts = last_commit_info.split('|')
        if len(parts) >= 5:
            stats['last_commit'] = {
                'hash': parts[0][:8],
                'author_name': parts[1],
                'author_email': parts[2],
                'date': parts[3],
                'message': parts[4]
            }
    
    # Get contributor stats (all time)
    contributors = run_git_command(repo_path, ['shortlog', '-sn', '--all'])
    if contributors:
        stats['contributor_count'] = len(contributors.split('\n'))
        stats['top_contributors'] = [
            {'name': line.strip().split('\t')[1], 'commits': int(line.strip().split('\t')[0])}
            for line in contributors.split('\n')[:5]
        ] if contributors else []
    
    return stats


def parse_diff_stat(diff_stat: str) -> Dict:
    """Parse git diff --shortstat output"""
    result = {
        'insertions': 0,
        'deletions': 0,
        'files_changed': 0
    }
    
    if not diff_stat:
        return result
    
    # Example: " 3 files changed, 45 insertions(+), 12 deletions(-)"
    parts = diff_stat.split(',')
    
    for part in parts:
        part = part.strip()
        if 'file' in part:
            result['files_changed'] = int(part.split()[0])
        elif 'insertion' in part:
            result['insertions'] = int(part.split()[0])
        elif 'deletion' in part:
            result['deletions'] = int(part.split()[0])
    
    return result


def scan_all_repositories() -> List[Dict]:
    """Scan all git repositories in projects directory"""
    repos = []
    
    if not os.path.exists(PROJECTS_ROOT):
        print(f"Projects directory not found: {PROJECTS_ROOT}", file=sys.stderr)
        return repos
    
    # Find all git repositories
    for item in os.listdir(PROJECTS_ROOT):
        item_path = os.path.join(PROJECTS_ROOT, item)
        if os.path.isdir(item_path) and os.path.exists(os.path.join(item_path, '.git')):
            print(f"Scanning repository: {item}")
            stats = get_repository_stats(item_path)
            repos.append(stats)
    
    return repos


def save_stats(stats: List[Dict]) -> None:
    """Save statistics to log file"""
    try:
        log_dir = Path(GIT_LOG_DIR)
        log_dir.mkdir(parents=True, exist_ok=True)
        
        # Daily log file
        log_file = log_dir / f'{DEV_USER}_git_stats_{datetime.now().strftime("%Y-%m-%d")}.jsonl'
        
        with open(log_file, 'a') as f:
            for stat in stats:
                f.write(json.dumps(stat) + '\n')
        
        print(f"Stats saved to: {log_file}")
        
        # Also save a "latest" snapshot
        latest_file = log_dir / f'{DEV_USER}_git_stats_latest.json'
        with open(latest_file, 'w') as f:
            json.dump({
                'timestamp': datetime.utcnow().isoformat(),
                'repositories': stats
            }, f, indent=2)
        
    except Exception as e:
        print(f"Error saving stats: {e}", file=sys.stderr)


def print_summary(stats: List[Dict]) -> None:
    """Print a human-readable summary"""
    print("\n" + "="*60)
    print(f"Git Statistics Summary - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*60)
    
    total_commits_24h = sum(s.get('commits_last_24h', 0) for s in stats)
    total_insertions = sum(s.get('loc_changes_24h', {}).get('insertions', 0) for s in stats)
    total_deletions = sum(s.get('loc_changes_24h', {}).get('deletions', 0) for s in stats)
    total_files_changed = sum(s.get('files_changed_24h', 0) for s in stats)
    
    print(f"\nRepositories scanned: {len(stats)}")
    print(f"\nLast 24 hours:")
    print(f"  Commits: {total_commits_24h}")
    print(f"  Files changed: {total_files_changed}")
    print(f"  Lines added: +{total_insertions}")
    print(f"  Lines deleted: -{total_deletions}")
    print(f"  Net change: {total_insertions - total_deletions:+d} lines")
    
    print("\nPer-repository breakdown:")
    for stat in stats:
        if 'error' in stat:
            print(f"  {stat['repository']}: {stat['error']}")
            continue
        
        loc = stat.get('loc_changes_24h', {})
        print(f"  {stat['repository']}:")
        print(f"    Commits (24h): {stat.get('commits_last_24h', 0)}")
        print(f"    LOC: +{loc.get('insertions', 0)} -{loc.get('deletions', 0)}")
        
        if stat.get('unstaged_files', 0) > 0 or stat.get('staged_files', 0) > 0:
            print(f"    Uncommitted: {stat.get('unstaged_files', 0)} unstaged, {stat.get('staged_files', 0)} staged")
    
    print("="*60 + "\n")


def main():
    """Main entry point"""
    print(f"Git Statistics Tracker for user: {DEV_USER}")
    print(f"Projects root: {PROJECTS_ROOT}")
    print(f"Log directory: {GIT_LOG_DIR}")
    print("")
    
    stats = scan_all_repositories()
    
    if not stats:
        print("No git repositories found")
        return
    
    save_stats(stats)
    print_summary(stats)


if __name__ == '__main__':
    main()
