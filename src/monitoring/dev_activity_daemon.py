#!/usr/bin/env python3
"""
Developer Activity Monitoring Daemon
Tracks file modifications, CPU usage, and triggers auto-shutdown on idle
"""

import os
import sys
import time
import json
import psutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List

# Configuration (loaded from environment or defaults)
DEV_USER = os.getenv('DEV_USER', 'jerry')
PROJECTS_ROOT = os.getenv('PROJECTS_ROOT', f'/home/{DEV_USER}/projects')
ACTIVITY_LOG_DIR = os.getenv('ACTIVITY_LOG_DIR', '/var/log/dev-activity')
CHECK_INTERVAL = int(os.getenv('CHECK_INTERVAL_SECONDS', '5')) # Check every 5 seconds
IDLE_SHUTDOWN_MINUTES = int(os.getenv('IDLE_SHUTDOWN_MINUTES', '30'))
CPU_IDLE_THRESHOLD = float(os.getenv('CPU_IDLE_THRESHOLD', '5.0'))

# Global state
last_activity_time = time.time()
last_net_io = psutil.net_io_counters() # Initialize net stats
activity_log_file = Path(ACTIVITY_LOG_DIR) / f'{DEV_USER}_activity.jsonl'
keystroke_log_file = Path(ACTIVITY_LOG_DIR) / 'keystrokes' / f'{DEV_USER}_keystrokes.log'
last_keystroke_count = 0


def log_activity(event_type: str, details: Dict) -> None:
    """Log activity event to JSONL file"""
    try:
        activity_log_file.parent.mkdir(parents=True, exist_ok=True)
        
        event = {
            'timestamp': datetime.utcnow().isoformat(),
            'user': DEV_USER,
            'event_type': event_type,
            'details': details
        }
        
        with open(activity_log_file, 'a') as f:
            f.write(json.dumps(event) + '\n')
    except Exception as e:
        print(f"Error logging activity: {e}", file=sys.stderr)


def get_keystroke_count() -> int:
    """Get approximate keystroke count from input device events"""
    try:
        # Count keyboard events from /dev/input/event* devices
        # This requires root and gives us raw input events
        result = subprocess.run(
            ['timeout', '0.5', 'evtest', '--query', '/dev/input/by-path/platform-i8042-serio-0-event-kbd', 'EV_KEY'],
            capture_output=True, 
            text=True,
            timeout=1
        )
        # If device is active, evtest will show events
        # For now, we'll use a simpler approach - check xinput
        
        # Alternative: check xinput for pointer/keyboard activity
        result = subprocess.run(
            ['xinput', 'query-state', '3'],  # Virtual core keyboard is usually id 3
            capture_output=True,
            text=True,
            timeout=1,
            env={'DISPLAY': ':0'}
        )
        # Count button/key press states
        # This is approximate but gives us activity indication
        return len([line for line in result.stdout.split('\n') if 'key[' in line and 'down' in line])
    except Exception:
        return 0


def capture_keystrokes() -> Dict:
    """Capture keystroke information for this interval"""
    global last_keystroke_count
    try:
        keystroke_log_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Start logkeys if not running (captures actual keystrokes)
        # Check if logkeys is installed and start it
        logkeys_log = keystroke_log_file.parent / 'logkeys.log'
        
        # Try to get keystroke count/activity
        keystroke_info = {
            'timestamp': datetime.utcnow().isoformat(),
            'interval_seconds': CHECK_INTERVAL,
            'keys_detected': 0,
            'keyboard_active': False
        }
        
        # Check if logkeys is running and count new keystrokes
        if logkeys_log.exists():
            try:
                with open(logkeys_log, 'r') as f:
                    content = f.read()
                    current_count = len(content)
                    keystroke_info['keys_detected'] = current_count - last_keystroke_count
                    last_keystroke_count = current_count
                    keystroke_info['keyboard_active'] = keystroke_info['keys_detected'] > 0
            except Exception:
                pass
        
        return keystroke_info
    except Exception as e:
        print(f"Keystroke capture failed: {e}", file=sys.stderr)
        return {'keys_detected': 0, 'keyboard_active': False}


def get_user_processes() -> List[Dict]:
    """Get all processes owned by the developer user"""
    processes = []
    try:
        for proc in psutil.process_iter(['pid', 'name', 'username', 'cpu_percent', 'memory_percent']):
            try:
                if proc.info['username'] == DEV_USER:
                    processes.append(proc.info)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
    except Exception as e:
        print(f"Error getting processes: {e}", file=sys.stderr)
    
    return processes


def get_cpu_usage() -> float:
    """Get overall CPU usage percentage"""
    try:
        return psutil.cpu_percent(interval=1)
    except Exception:
        return 0.0


def get_modified_files(since_time: float) -> List[str]:
    """Get files modified since a given timestamp in projects directory"""
    modified_files = []
    
    if not os.path.exists(PROJECTS_ROOT):
        return modified_files
    
    try:
        for root, dirs, files in os.walk(PROJECTS_ROOT):
            # Skip hidden directories and .git
            dirs[:] = [d for d in dirs if not d.startswith('.')]
            
            for file in files:
                if file.startswith('.'):
                    continue
                    
                filepath = os.path.join(root, file)
                try:
                    mtime = os.path.getmtime(filepath)
                    if mtime > since_time:
                        rel_path = os.path.relpath(filepath, PROJECTS_ROOT)
                        modified_files.append(rel_path)
                except (OSError, ValueError):
                    continue
    except Exception as e:
        print(f"Error scanning files: {e}", file=sys.stderr)
    
    return modified_files


def check_git_activity() -> Dict:
    """Check for recent git commits"""
    try:
        result = subprocess.run(
            ['git', '-C', PROJECTS_ROOT, 'log', '--all', '--since=1 hour ago', '--oneline'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        commits = result.stdout.strip().split('\n') if result.stdout.strip() else []
        return {
            'recent_commits': len(commits),
            'has_activity': len(commits) > 0
        }
    except Exception:
        return {'recent_commits': 0, 'has_activity': False}


def get_x11_idle_time() -> int:
    """Get X11 idle time in milliseconds using xprintidle"""
    try:
        # Try common displays
        for display in [':0', ':1']:
            cmd = ['sudo', '-u', DEV_USER, 'env', f'DISPLAY={display}', 'xprintidle']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                return int(result.stdout.strip())
    except Exception:
        pass
    return 999999999 # High value (idle)


def is_system_active() -> tuple[bool, Dict]:
    """
    Determine if the system shows signs of activity
    Returns (is_active, details)
    """
    global last_net_io
    details = {}
    
    # Check Network I/O
    curr_net_io = psutil.net_io_counters()
    details['net_sent_bytes'] = curr_net_io.bytes_sent - last_net_io.bytes_sent
    details['net_recv_bytes'] = curr_net_io.bytes_recv - last_net_io.bytes_recv
    last_net_io = curr_net_io
    
    # Check CPU usage
    cpu_usage = get_cpu_usage()
    details['cpu_usage'] = cpu_usage
    
    # Check X11 Idle (Keystrokes/Mouse)
    x11_idle_ms = get_x11_idle_time()
    details['x11_idle_ms'] = x11_idle_ms
    details['user_active_physically'] = x11_idle_ms < (CHECK_INTERVAL * 1000)
    
    # Capture keystroke activity
    keystroke_info = capture_keystrokes()
    details['keystroke_count'] = keystroke_info['keys_detected']
    details['keyboard_active'] = keystroke_info['keyboard_active']
    
    # Check user processes
    processes = get_user_processes()
    details['process_count'] = len(processes)
    
    # Track high CPU processes AND file transfer tools specifically
    transfer_tools = {'scp', 'sftp', 'rsync', 'ftp', 'curl', 'wget'}
    details['active_processes'] = [
        p['name'] for p in processes 
        if p['cpu_percent'] > 0.1 or p['name'] in transfer_tools
    ]
    
    # Check for SSH sessions
    ssh_sessions = 0
    try:
        result = subprocess.run(['who'], capture_output=True, text=True, timeout=2)
        ssh_sessions = result.stdout.count(DEV_USER)
    except Exception:
        pass
    details['ssh_sessions'] = ssh_sessions
    
    # Check for modified files (in last interval)
    modified_files = get_modified_files(time.time() - CHECK_INTERVAL)
    details['modified_files'] = len(modified_files)
    details['files'] = modified_files[:10]  # First 10 files
    
    # Determine if active
    is_active = (
        cpu_usage > CPU_IDLE_THRESHOLD or
        ssh_sessions > 0 or
        len(modified_files) > 0 or
        len(details['active_processes']) > 0 or
        details['user_active_physically']
    )
    
    return is_active, details


def take_screenshot() -> None:
    """Take a screenshot if active"""
    screenshot_dir = Path(ACTIVITY_LOG_DIR) / 'screenshots'
    try:
        screenshot_dir.mkdir(exist_ok=True)
        # Set ownership to user so they can read/sync them (or root?)
        # Daemon runs as root, so files will be root.
        # We should chown them to dev user if we want them to sync via user-level tools, 
        # but our sync script runs as root, so it's fine.
        
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        filename = f"{timestamp}.png"
        filepath = screenshot_dir / filename
        
        # Only take screenshot if we haven't in the last 5 minutes?
        # The main loop runs every 60s (CHECK_INTERVAL).
        # Taking one every minute is fine.
        
        for display in [':0', ':1']:
            xauth_path = f'/home/{DEV_USER}/.Xauthority'
            cmd = ['sudo', '-u', DEV_USER, 'env', f'DISPLAY={display}', f'XAUTHORITY={xauth_path}', 'scrot', str(filepath)]
            res = subprocess.run(cmd, capture_output=True, timeout=5)
            if res.returncode == 0:
                break

    except Exception as e:
        print(f"Screenshot failed: {e}", file=sys.stderr)


def trigger_shutdown() -> None:
    """Trigger system shutdown with pre-shutdown backup"""
    print(f"\n{'='*50}")
    print(f"IDLE SHUTDOWN SEQUENCE INITIATED")
    print(f"{'='*50}")
    
    # Step 1: Log pre-shutdown backup intent
    log_activity('pre_shutdown_backup_start', {
        'reason': 'idle_timeout',
        'idle_minutes': IDLE_SHUTDOWN_MINUTES
    })
    
    print("Step 1/4: Committing uncommitted Git changes...")
    
    # Step 1.5: Auto-commit any uncommitted changes in all repos
    git_backup_success = False
    try:
        repos_backed_up = 0
        for repo_dir in Path(PROJECTS_ROOT).rglob('.git'):
            repo_path = repo_dir.parent
            try:
                # Check for uncommitted changes
                status_result = subprocess.run(
                    ['git', '-C', str(repo_path), 'status', '--porcelain'],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if status_result.stdout.strip():
                    # Has uncommitted changes - commit them
                    subprocess.run(
                        ['git', '-C', str(repo_path), 'add', '-A'],
                        timeout=10
                    )
                    subprocess.run(
                        ['git', '-C', str(repo_path), 'commit', '-m', 
                         f'Auto-commit before idle shutdown at {datetime.utcnow().isoformat()}'],
                        timeout=10
                    )
                    repos_backed_up += 1
                    print(f"  ✓ Auto-committed changes in {repo_path.name}")
            except Exception as e:
                print(f"  ⚠ Failed to backup {repo_path.name}: {e}")
        
        git_backup_success = True
        print(f"  ✓ Git backup complete - {repos_backed_up} repos saved")
    except Exception as e:
        print(f"  ⚠ Git backup error: {e}")
    
    log_activity('pre_shutdown_git_backup', {
        'success': git_backup_success,
        'timestamp': datetime.now().isoformat()
    })
    
    print("Step 2/4: Running pre-shutdown file backup...")
    
    # Step 2: Run backup before shutdown
    backup_success = False
    try:
        # Run the backup script
        result = subprocess.run(
            ['bash', '/opt/dev-monitoring/dev_local_backup.sh'],
            timeout=300,  # 5 minute timeout
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            backup_success = True
            print("  ✓ Pre-shutdown backup completed successfully")
        else:
            print(f"  ⚠ Backup failed: {result.stderr}")
    except subprocess.TimeoutExpired:
        print("  ⚠ Backup timeout (5 minutes exceeded)")
    except Exception as e:
        print(f"  ⚠ Backup error: {e}")
    
    # Log backup completion
    log_activity('pre_shutdown_backup_complete', {
        'success': backup_success,
        'timestamp': datetime.now().isoformat()
    })
    
    # Step 3: Log shutdown
    log_activity('auto_shutdown', {
        'reason': 'idle_timeout',
        'idle_minutes': IDLE_SHUTDOWN_MINUTES,
        'git_backup_completed': git_backup_success,
        'backup_completed': backup_success
    })
    
    print(f"Step 3/4: Backups complete (git={git_backup_success}, files={backup_success})")
    print(f"Step 4/4: Triggering system shutdown in 1 minute...")
    print(f"{'='*50}\n")
    
    try:
        subprocess.run(['sudo', 'shutdown', '-h', '+1', 'Auto-shutdown due to inactivity'], check=True)
    except Exception as e:
        print(f"Error triggering shutdown: {e}", file=sys.stderr)


def main():
    """Main daemon loop"""
    global last_activity_time
    
    print(f"Starting activity monitor for user: {DEV_USER}")
    print(f"Projects root: {PROJECTS_ROOT}")
    print(f"Check interval: {CHECK_INTERVAL}s")
    print(f"Idle shutdown: {IDLE_SHUTDOWN_MINUTES} minutes")
    print(f"CPU idle threshold: {CPU_IDLE_THRESHOLD}%")
    print(f"Log file: {activity_log_file}")
    print("")
    
    log_activity('daemon_start', {
        'check_interval': CHECK_INTERVAL,
        'idle_shutdown_minutes': IDLE_SHUTDOWN_MINUTES
    })
    
    consecutive_idle_checks = 0
    max_idle_checks = (IDLE_SHUTDOWN_MINUTES * 60) // CHECK_INTERVAL
    
    while True:
        try:
            is_active, details = is_system_active()
            
            if is_active:
                # System is active
                last_activity_time = time.time()
                consecutive_idle_checks = 0
                
                log_activity('activity_detected', details)
                take_screenshot()
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Active - "
                      f"CPU: {details['cpu_usage']:.1f}%, "
                      f"Processes: {details['process_count']}, "
                      f"Modified files: {details['modified_files']}")
            else:
                # System is idle
                consecutive_idle_checks += 1
                idle_minutes = (consecutive_idle_checks * CHECK_INTERVAL) / 60
                
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Idle - "
                      f"{idle_minutes:.1f}/{IDLE_SHUTDOWN_MINUTES} minutes")
                
                # Check if we should shut down
                if consecutive_idle_checks >= max_idle_checks:
                    print(f"\n{'='*50}")
                    print(f"IDLE THRESHOLD REACHED: {IDLE_SHUTDOWN_MINUTES} minutes")
                    print(f"{'='*50}\n")
                    trigger_shutdown()
                    break
            
            # Sleep until next check
            time.sleep(CHECK_INTERVAL)
            
        except KeyboardInterrupt:
            print("\nShutdown requested by user")
            log_activity('daemon_stop', {'reason': 'user_interrupt'})
            break
        except Exception as e:
            print(f"Error in main loop: {e}", file=sys.stderr)
            time.sleep(CHECK_INTERVAL)


if __name__ == '__main__':
    main()
