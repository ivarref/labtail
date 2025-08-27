#!/usr/bin/env python3
import subprocess
import traceback
import sys

LINE_PREFIX_TO_PATCH = 'curl -LsSf https://raw.githubusercontent.com/ivarref/labtail/'
LINE_POSTFIX = '/labtail.sh -O \\'
RELEASE_MAJOR_MINOR_STR = "0.1"

def log_error(m):
    print(m, flush=True)

def exec_verbose(args, print_sout=False, return_sout=False):
    try:
        res = subprocess.run(args, capture_output=True)
        if res.returncode != 0:
            log_error(f'Command {args}')
            log_error(f'Failed with exit code {res.returncode}')
            if 0 == len(res.stdout.splitlines()):
                log_error('Stdout: <empty>')
            else:
                log_error('*'*25 + ' start stdout ' + '*'*25)
                for lin in res.stdout.splitlines():
                    try:
                        lin_decoded = lin.decode('utf-8')
                        log_error(lin_decoded)
                    except UnicodeDecodeError:
                        log_error(lin)
                log_error('*'*26 + ' end stdout ' + '*'*26)
            if 0 == len(res.stderr.splitlines()):
                log_error('Stderr: <empty>')
            else:
                log_error('*'*25 + ' start stderr ' + '*'*25)
                for lin in res.stderr.splitlines():
                    try:
                        lin_decoded = lin.decode('utf-8')
                        log_error(lin_decoded)
                    except UnicodeDecodeError:
                        log_error(lin)
                log_error('*'*26 + ' end stderr ' + '*'*26)
            log_error(f'Command {args} failed with exit code {res.returncode}')
            return False
        else:
            # info(f'CMD {str(args)} succeeded')
            sout = ''
            for lin in res.stdout.splitlines():
                try:
                    sout += lin.decode('utf-8')
                except UnicodeDecodeError:
                    sout += str(lin)
                sout += '\n'
            if print_sout:
                print(sout)
            if return_sout:
                return sout
            else:
                return True
    except FileNotFoundError as e:
        log_error(f'Executeable "{args[0]}" was not found!')
        log_error(f'Full command: {args}')
        raise e

def do_release():
    if False == exec_verbose(["git", "update-index", "--refresh"]):
        print("There are pending changes (update-index). Aborting release!")
        return False
    else:
        if False == exec_verbose(["git", "diff-index", "--quiet", "HEAD", "--"]):
            print("There are pending changes (diff-index). Aborting release!")
            return False
        else:
            print("No changes / pending changes. Good!")
            git_sha = exec_verbose(["git", "rev-parse", "--verify", "HEAD"], return_sout=True)
            if False == git_sha:
                print("Could not get git sha!")
                return False
            else:
                git_sha = git_sha.strip()
                print(f"git sha is '{git_sha}'")
                new_lines = []
                found = False
                with open('README.md', 'r', encoding='utf-8') as fd:
                    for lin in fd.readlines():
                        lin = lin.rstrip('\n')
                        global LINE_PREFIX_TO_PATCH
                        global LINE_POSTFIX
                        if lin.startswith(LINE_PREFIX_TO_PATCH):
                            print(f"Patching line:\n{lin}")
                            new_line = '''
                            $PREFIX$SHA$POSTFIX
                            '''.replace('$PREFIX', LINE_PREFIX_TO_PATCH).replace('$SHA', git_sha).replace('$POSTFIX', LINE_POSTFIX)
                            new_line = new_line.strip()
                            print(f"{new_line}")
                            print(f"^^^ patched line")
                            found = True
                            new_lines.append(new_line)
                        else:
                            new_lines.append(lin)
                if False == found:
                    print('Did not find line to patch in README.md. Aborting!')
                    return False
                else:
                    if '--dry' in sys.argv:
                        print('Dry mode, exiting!')
                        return False
                    else:
                        with open('README.md', 'w', encoding='utf-8') as fd:
                            fd.write('\n'.join(new_lines))
                            fd.write('\n')
                        print('Updated README.md')
                        if False == exec_verbose(['git', 'add', 'README.md']):
                            print('Failed to git add README.md')
                            return False
                        else:
                            print('git add README.md OK')
                            cmd = ['git', 'commit', '-m', f"Make release"]
                            if False == exec_verbose(cmd):
                                print('Failed to git commit. Aborting!')
                                return False
                            else:
                                print("OK commit: " + " ".join(cmd))
                                cmd = ['git', 'push']
                                if False == exec_verbose(cmd):
                                    print('Failed to git push. Aborting!')
                                    return False
                                else:
                                    print("OK push: " + " ".join(cmd))
                                    print(f"Released sha {git_sha}")
                                    return True
    print('should not get here')
    sys.exit(1)

if __name__ == "__main__":
    print("Releasing ...")
    try:
        ret = do_release()
        if '--dry' in sys.argv:
            pass
        else:
            if ret:
                print("Releasing ... Done")
            else:
                print("Releasing ... Failed!")
    except Exception as e:
        traceback.print_exc()
        print("Releasing ... Fatal error!")
        sys.exit(1)