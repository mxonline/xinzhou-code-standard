<?php

declare(strict_types=1);

/**
 * Z-Blog plugin user-facing terminology gate.
 *
 * Copy to tools/check-ui-terminology.php in a plugin repository.
 * Optional project config: config/ui-terminology.json
 * Exit code 1 means UI Terminology Gate BLOCKED.
 */

$root = realpath(__DIR__ . '/..') ?: getcwd();
$configPath = $root . DIRECTORY_SEPARATOR . 'config' . DIRECTORY_SEPARATOR . 'ui-terminology.json';

$rules = [
    'blocking_patterns' => [
        '字段\\s*\\d+',
        '\\bDurationMs\\b',
        '\\bPathKey\\b',
        '\\bKeyset\\b',
        '\\bOFFSET\\b',
        '\\bcursor\\b',
        '\\bmigration\\b',
        '\\bbackfill\\b',
        '\\bReferer\\b',
        '\\bBrowser\\b',
        '\\bDevice\\b',
        '\\bCampaign\\b',
        '\\bAI\\s+crawler\\b',
        '规范化\\s*Path',
        '下钻',
        '\\bP(?:50|75|95)\\b',
    ],
    'contextual_terms' => ['RUM', 'LCP', 'INP', 'CLS', 'TTFB', 'FCP', 'Beacon', 'CIDR', 'Header', 'Path'],
    'internal_enum_patterns' => [
        '\\bdirect\\b', '\\bsearch\\b', '\\bsocial\\b', '\\bexternal\\b', '\\binternal\\b',
        '\\bdesktop\\b', '\\bmobile\\b', '\\btablet\\b',
    ],
    'exclude' => ['vendor/', 'node_modules/', 'tests/', 'test/', 'migrations/', 'docs/', '.git/'],
    'allow_marker' => 'ui-term:allow',
];

if (is_file($configPath)) {
    $projectRules = json_decode((string) file_get_contents($configPath), true);
    if (!is_array($projectRules)) {
        fwrite(STDERR, "Invalid JSON: {$configPath}\n");
        exit(2);
    }
    foreach (['blocking_patterns', 'contextual_terms', 'internal_enum_patterns', 'exclude'] as $key) {
        if (isset($projectRules[$key]) && is_array($projectRules[$key])) {
            $rules[$key] = array_values(array_unique(array_merge($rules[$key], $projectRules[$key])));
        }
    }
    if (!empty($projectRules['allow_marker']) && is_string($projectRules['allow_marker'])) {
        $rules['allow_marker'] = $projectRules['allow_marker'];
    }
}

function uiTermExcluded(string $relative, array $exclude): bool
{
    $normalized = str_replace('\\', '/', $relative);
    foreach ($exclude as $prefix) {
        if (str_contains($normalized, $prefix)) {
            return true;
        }
    }
    return false;
}

function uiTermTextNodes(string $html): array
{
    $parts = preg_split('/<[^>]*>/u', $html) ?: [];
    $nodes = [];
    foreach ($parts as $part) {
        $part = html_entity_decode(trim($part), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        if ($part !== '') {
            $nodes[] = $part;
        }
    }
    return $nodes;
}

function uiTermPhpSnippets(string $source): array
{
    $snippets = [];
    $tokens = token_get_all($source);
    $line = 1;
    $echoMode = false;

    foreach ($tokens as $token) {
        if (is_string($token)) {
            if ($token === ';') {
                $echoMode = false;
            }
            continue;
        }

        [$id, $text, $tokenLine] = $token;
        $line = $tokenLine;

        if ($id === T_INLINE_HTML) {
            foreach (uiTermTextNodes($text) as $node) {
                $snippets[] = [$line, $node];
            }
            continue;
        }

        if ($id === T_ECHO || $id === T_PRINT) {
            $echoMode = true;
            continue;
        }

        if ($echoMode && $id === T_CONSTANT_ENCAPSED_STRING) {
            $literal = trim($text, "'\"");
            if (str_contains($literal, '<')) {
                foreach (uiTermTextNodes($literal) as $node) {
                    $snippets[] = [$line, $node];
                }
            } elseif (trim($literal) !== '') {
                $snippets[] = [$line, $literal];
            }
        }
    }

    return $snippets;
}

function uiTermJsSnippets(string $source): array
{
    $snippets = [];
    $lines = preg_split('/\\R/u', $source) ?: [];
    $sink = '/(?:textContent|innerHTML|insertAdjacentHTML|setAttribute\\s*\\(\\s*[\'\"](?:title|aria-label)|alert\\s*\\(|confirm\\s*\\()/i';

    foreach ($lines as $index => $line) {
        if (!preg_match($sink, $line)) {
            continue;
        }
        if (preg_match_all('/([\'\"])(.*?)\\1|`([^`]*)`/u', $line, $matches, PREG_SET_ORDER)) {
            foreach ($matches as $match) {
                $text = isset($match[3]) && $match[3] !== '' ? $match[3] : ($match[2] ?? '');
                foreach (uiTermTextNodes($text) as $node) {
                    $snippets[] = [$index + 1, $node];
                }
            }
        }
    }

    return $snippets;
}

function uiTermHasChinese(string $text): bool
{
    return preg_match('/[\\x{3400}-\\x{9FFF}]/u', $text) === 1;
}

function uiTermCheck(string $file, int $line, string $text, array $rules, array &$issues): void
{
    if (str_contains($text, $rules['allow_marker'])) {
        return;
    }

    foreach ($rules['blocking_patterns'] as $pattern) {
        if (@preg_match('/' . $pattern . '/iu', $text) === 1) {
            $issues[] = [$file, $line, $pattern, $text];
        }
    }

    foreach ($rules['internal_enum_patterns'] as $pattern) {
        if (@preg_match('/' . $pattern . '/iu', $text) === 1) {
            $issues[] = [$file, $line, $pattern, $text];
        }
    }

    foreach ($rules['contextual_terms'] as $term) {
        if (preg_match('/\\b' . preg_quote($term, '/') . '\\b/iu', $text) === 1 && !uiTermHasChinese($text)) {
            $issues[] = [$file, $line, $term . ' requires Chinese context', $text];
        }
    }
}

$issues = [];
$iterator = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)
);

foreach ($iterator as $fileInfo) {
    if (!$fileInfo->isFile()) {
        continue;
    }
    $path = $fileInfo->getPathname();
    $relative = ltrim(str_replace('\\', '/', substr($path, strlen($root))), '/');
    if (uiTermExcluded($relative, $rules['exclude'])) {
        continue;
    }

    $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
    if (!in_array($ext, ['php', 'js', 'html', 'htm'], true)) {
        continue;
    }

    $source = (string) file_get_contents($path);
    if ($source === '') {
        continue;
    }

    if ($ext === 'php') {
        $snippets = uiTermPhpSnippets($source);
    } elseif ($ext === 'js') {
        $snippets = uiTermJsSnippets($source);
    } else {
        $snippets = [];
        $lines = preg_split('/\\R/u', $source) ?: [];
        foreach ($lines as $index => $htmlLine) {
            foreach (uiTermTextNodes($htmlLine) as $node) {
                $snippets[] = [$index + 1, $node];
            }
        }
    }

    foreach ($snippets as [$line, $text]) {
        uiTermCheck($relative, (int) $line, $text, $rules, $issues);
    }
}

if ($issues !== []) {
    fwrite(STDERR, "UI Terminology Gate: BLOCKED\n");
    foreach ($issues as [$file, $line, $rule, $text]) {
        $preview = mb_strlen($text, 'UTF-8') > 120 ? mb_substr($text, 0, 117, 'UTF-8') . '...' : $text;
        fwrite(STDERR, sprintf("%s:%d [%s] %s\n", $file, $line, $rule, $preview));
    }
    exit(1);
}

echo "UI Terminology Gate: PASS\n";
