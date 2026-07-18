// Static integrity checks for the repo-hosted agent plugin
// (plugins/bug-handler) and both marketplace catalogs.
//
// Run from the repository root:
//   dart tool/validate_plugin.dart
//
// Exit code 0 = all checks passed; 1 = one or more failures (each printed).
// Requires no credentials, network access, or non-SDK dependencies, so it can
// run in any CI. Platform validators (claude plugin validate --strict, codex
// plugin marketplace add) complement this; they are not replaced by it.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const pluginRoot = 'plugins/bug-handler';
final _failures = <String>[];

void fail(String message) => _failures.add(message);

void check(bool condition, String message) {
  if (!condition) fail(message);
}

String? readFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('missing file: $path');
    return null;
  }
  return file.readAsStringSync();
}

Map<String, dynamic>? readJson(String path) {
  final raw = readFile(path);
  if (raw == null) return null;
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } on FormatException catch (e) {
    fail('$path: invalid JSON (${e.message})');
    return null;
  }
}

final _kebab = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Frontmatter parser for the exact shape this repo standardizes on
/// (see AGENTS.md): name plain scalar, description folded `>-` block.
({String name, String description})? parseFrontmatter(String path, String raw) {
  final lines = raw.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    fail('$path: frontmatter must start with ---');
    return null;
  }
  final end = lines.indexWhere((l) => l.trim() == '---', 1);
  if (end == -1) {
    fail('$path: frontmatter not closed with ---');
    return null;
  }
  final fm = lines.sublist(1, end);
  if (fm.isEmpty || !fm.first.startsWith('name: ')) {
    fail('$path: first frontmatter field must be `name: <kebab-case>`');
    return null;
  }
  final name = fm.first.substring('name: '.length).trim();
  if (fm.length < 2 || fm[1].trim() != 'description: >-') {
    fail('$path: description must use the folded block form `description: >-` '
        '(plain scalars break YAML on `:` and quotes)');
    return null;
  }
  final descLines = <String>[];
  for (final line in fm.skip(2)) {
    if (!line.startsWith('  ')) {
      fail('$path: unexpected frontmatter line `$line` '
          '(only name + folded description are allowed)');
      return null;
    }
    descLines.add(line.trim());
  }
  return (name: name, description: descLines.join(' '));
}

void main() {
  if (!File('pubspec.yaml').existsSync() ||
      !Directory(pluginRoot).existsSync()) {
    print('error: run from the bug_handler repository root');
    exit(2);
  }

  // --- pubspec version -------------------------------------------------------
  final pubspec = readFile('pubspec.yaml') ?? '';
  final versionMatch =
      RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
  final packageVersion = versionMatch?.group(1);
  check(packageVersion != null, 'pubspec.yaml: no version field found');

  // --- manifests -------------------------------------------------------------
  final claudePlugin = readJson('$pluginRoot/.claude-plugin/plugin.json');
  final codexPlugin = readJson('$pluginRoot/.codex-plugin/plugin.json');
  final claudeMarket = readJson('.claude-plugin/marketplace.json');
  final codexMarket = readJson('.agents/plugins/marketplace.json');

  for (final (label, manifest) in [
    ('$pluginRoot/.claude-plugin/plugin.json', claudePlugin),
    ('$pluginRoot/.codex-plugin/plugin.json', codexPlugin),
  ]) {
    if (manifest == null) continue;
    for (final field in ['name', 'version', 'description']) {
      check(manifest[field] is String && (manifest[field] as String).isNotEmpty,
          '$label: `$field` must be a non-empty string');
    }
    check(_kebab.hasMatch(manifest['name'] as String? ?? ''),
        '$label: name must be kebab-case');
    check(manifest['author'] is Map,
        '$label: `author` must be an object ({"name": ...}), not a string');
    check(manifest['version'] == packageVersion,
        '$label: version ${manifest['version']} != pubspec $packageVersion');
  }
  if (claudePlugin != null && codexPlugin != null) {
    check(claudePlugin['name'] == codexPlugin['name'],
        'plugin manifests disagree on name');
    check(claudePlugin['description'] == codexPlugin['description'],
        'plugin manifests disagree on description');
  }

  // --- marketplaces ----------------------------------------------------------
  final pluginName = claudePlugin?['name'] as String? ?? 'bug-handler';
  if (claudeMarket != null) {
    check(_kebab.hasMatch(claudeMarket['name'] as String? ?? ''),
        '.claude-plugin/marketplace.json: name must be kebab-case');
    check(claudeMarket['owner'] is Map,
        '.claude-plugin/marketplace.json: owner must be an object');
    final meta = claudeMarket['metadata'];
    if (meta is Map && meta['version'] != null) {
      check(meta['version'] == packageVersion,
          '.claude-plugin/marketplace.json: metadata.version != pubspec');
    }
    final entries = (claudeMarket['plugins'] as List?) ?? const [];
    check(entries.isNotEmpty, '.claude-plugin/marketplace.json: no plugins');
    final names = <String>{};
    for (final e in entries.cast<Map<String, dynamic>>()) {
      final name = e['name'] as String? ?? '';
      check(names.add(name),
          '.claude-plugin/marketplace.json: duplicate plugin name $name');
      final source = e['source'];
      if (source is String) {
        check(!source.contains('..'),
            '.claude-plugin/marketplace.json: source must not traverse with ..');
        check(Directory(source).existsSync(),
            '.claude-plugin/marketplace.json: source path $source does not exist');
      }
      if (name == pluginName) {
        check(e['version'] == packageVersion,
            '.claude-plugin/marketplace.json: entry version != pubspec');
      }
    }
  }
  if (codexMarket != null) {
    final entries = (codexMarket['plugins'] as List?) ?? const [];
    check(entries.isNotEmpty, '.agents/plugins/marketplace.json: no plugins');
    var found = false;
    for (final e in entries.cast<Map<String, dynamic>>()) {
      if (e['name'] == pluginName) found = true;
      final source = e['source'];
      if (source is Map && source['source'] == 'local') {
        final path = source['path'] as String? ?? '';
        check(!path.contains('..'),
            '.agents/plugins/marketplace.json: source path must not use ..');
        check(Directory(path).existsSync(),
            '.agents/plugins/marketplace.json: source path $path does not exist');
      }
    }
    check(
        found, '.agents/plugins/marketplace.json: no entry named $pluginName');
  }

  // --- skills ----------------------------------------------------------------
  final skillsDir = Directory('$pluginRoot/skills');
  final skillDirs = skillsDir.existsSync()
      ? (skillsDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <Directory>[];
  check(skillDirs.isNotEmpty, '$pluginRoot/skills: no skills found');
  final skillNames = <String>{};
  for (final dir in skillDirs) {
    final dirName = dir.path.split(Platform.pathSeparator).last;
    final skillPath = '${dir.path}/SKILL.md';
    check(_kebab.hasMatch(dirName), '$skillPath: dir name must be kebab-case');
    final raw = readFile(skillPath);
    if (raw == null) continue;
    final fm = parseFrontmatter(skillPath, raw);
    if (fm == null) continue;
    check(fm.name == dirName,
        '$skillPath: frontmatter name `${fm.name}` != directory `$dirName`');
    check(skillNames.add(fm.name), '$skillPath: duplicate skill name');
    check(
        fm.description.length <= 1024,
        '$skillPath: description ${fm.description.length} chars (max 1024 for '
        'cross-platform frontmatter budget)');
    check(
        fm.description.startsWith('Use when'),
        '$skillPath: description should state triggering conditions '
        '("Use when ...")');

    // Relative file references (`../../references/x.md`) must resolve inside
    // the plugin root - broken links and traversal both fail installs.
    for (final m in RegExp(r'`((?:\.\./)+[\w\-./]+)`').allMatches(raw)) {
      final ref = m.group(1)!;
      final refPath = '${dir.path}/$ref';
      check(FileSystemEntity.typeSync(refPath) != FileSystemEntityType.notFound,
          '$skillPath: referenced path $ref not found');
      final canonical = File(refPath).absolute.uri.normalizePath().toFilePath();
      final rootCanonical =
          Directory(pluginRoot).absolute.uri.normalizePath().toFilePath();
      check(canonical.startsWith(rootCanonical),
          '$skillPath: reference $ref escapes the plugin root');
    }
  }

  // --- hygiene over the whole plugin tree ------------------------------------
  final secretPatterns = <String, RegExp>{
    'AWS access key': RegExp(r'\b(AKIA|ASIA)[0-9A-Z]{16}\b'),
    'GitHub token': RegExp(r'\bghp_[A-Za-z0-9]{36}\b'),
    'private key block': RegExp('BEGIN (RSA|EC|OPENSSH) PRIVATE KEY'),
  };
  for (final entity in Directory(pluginRoot).listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = entity.path;
    final content = entity.readAsStringSync();
    check(!content.contains('/Users/') && !content.contains(r'C:\'),
        '$rel: contains an absolute local path');
    for (final MapEntry(key: label, value: pattern) in secretPatterns.entries) {
      check(
          !pattern.hasMatch(content), '$rel: matches secret pattern ($label)');
    }
  }

  // --- pub.dev archive boundary ----------------------------------------------
  final pubignore = readFile('.pubignore');
  if (pubignore != null) {
    for (final required in ['plugins/', '.claude-plugin/', '.agents/']) {
      check(
          pubignore.contains(required),
          '.pubignore: must exclude $required (a partial plugin tree in the '
          'pub archive would ship skills without their manifests)');
    }
  }

  // --- result ----------------------------------------------------------------
  if (_failures.isEmpty) {
    print('plugin validation passed '
        '(${skillDirs.length} skills, version $packageVersion)');
    return;
  }
  print('plugin validation FAILED:');
  for (final f in _failures) {
    print('  - $f');
  }
  exit(1);
}
