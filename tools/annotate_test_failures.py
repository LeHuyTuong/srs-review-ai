"""Turn a dart test JSON report into GitHub ::error annotations.

Why this exists: GitHub only serves Actions logs to signed-in users, so a red
run on a public repo shows "N tests passed, 1 failed" and nothing else. Check
annotations ARE public, so `flutter test --file-reporter` writes the JSON and
this script re-emits every failure as one trimmed annotation carrying the test
name, its source file, and the first lines of the error.

Usage: python3 annotate_test_failures.py path/to/report.json
"""
import json
import sys


def esc(text):
    """Escape a workflow-command message (newlines must stay on one line)."""
    text = text.replace('%', '%25')
    text = text.replace('\r', '%0D')
    text = text.replace('\n', '%0A')
    return text


def repo_path(url):
    """file:// URL of a suite -> repo-relative path ('app/test/...') or ''."""
    if not url or not url.startswith('file:'):
        return ''
    path = url[5:]
    if path.startswith('//'):
        path = path[2:]
    # Suites live under app/ (the jobs run with working-directory: app), and
    # the URL is absolute, so the last '/app/' segment marks the repo root.
    idx = path.rfind('/app/')
    if idx == -1:
        return ''
    return 'app' + path[idx + 4:]


def main(argv):
    report = argv[1] if len(argv) > 1 else 'test_report.json'
    try:
        with open(report, encoding='utf-8') as fh:
            events = [json.loads(line) for line in fh if line.strip()]
    except (OSError, ValueError) as exc:
        print('::error::test report unavailable: %s' % esc(str(exc)))
        return

    tests = {}
    errors = {}
    results = {}
    for event in events:
        kind = event.get('type')
        if kind == 'testStart' and event.get('test'):
            tests[event['test']['id']] = event['test']
        elif kind == 'error':
            errors.setdefault(event.get('testID'), []).append(
                str(event.get('error', '')))
        elif kind == 'testDone':
            results[event.get('testID')] = event.get('result')

    failed = sorted(
        {tid for tid, res in results.items() if res in ('failure', 'error')}
        | set(errors))
    if not failed:
        print('::notice::test report contains no failures')
        return

    for tid in failed:
        test = tests.get(tid, {})
        name = esc(test.get('name') or 'unknown test')
        location = repo_path(test.get('url'))
        head = (errors.get(tid) or ['(no message captured)'])[0]
        lines = [ln.strip() for ln in head.splitlines() if ln.strip()][:25]
        body = esc(' | '.join(lines) or '(no message captured)')
        if len(body) > 3000:
            body = body[:3000] + '...'
        prefix = 'file=%s,' % location if location else ''
        print('::error %stitle=Flutter test failed::%s :: %s'
              % (prefix, name, body))


if __name__ == '__main__':
    main(sys.argv)
