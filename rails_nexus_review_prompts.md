# RailsNexus Codex Implementation Prompts

Use these prompts in order. Each prompt is intentionally focused so Codex can implement and verify one group of changes safely.

## 1. Secure authentication globally

```text
Review the `tamiru/rails_nexus` Rails engine and fix its dashboard authentication.

Requirements:
- Make authentication fail closed.
- When `RailsNexus.configuration.auth_block` is missing, every RailsNexus controller must return `403 Forbidden`.
- Apply authentication globally from `RailsNexus::ApplicationController`.
- Remove duplicated `verify_access` methods from individual controllers.
- Ensure `WorkflowController` and `SourceCodeController` are protected.
- Do not interfere with the host application's authentication implementation.
- Preserve support for authentication blocks such as `->(controller) { controller.current_user&.admin? }`.
- Update the README so its documented behavior exactly matches the implementation.
- Add integration tests covering a missing `auth_block`, a block returning false, a block returning true, workflow endpoints, and the source-code endpoint.
- Run the complete test suite and report the changed files and test results.
```

## 2. Eliminate backup command injection

```text
Audit and refactor `RailsNexus::BackupService` to eliminate shell-command injection.

Requirements:
- Never build shell commands by joining user-controlled values into a string.
- Invoke executables using argument arrays, for example `Open3.capture3(env, *command)`.
- Apply this to MySQL, PostgreSQL, SQLite, MongoDB, Redis, tar, rsync, OpenSSL, GPG, split, and every other external command.
- Do not expose database or encryption passwords in the process list.
- Use environment variables or securely permissioned temporary configuration files where needed.
- Avoid `shellwords` as the primary protection; prefer structured arguments.
- Replace free-form `mysql_additional_options` with safely parsed and validated options. Reject dangerous or unsupported arguments.
- Validate database names, table names, ports, remote hosts, and filesystem paths.
- Preserve existing backup features and the existing result format.
- Add tests using malicious values containing semicolons, command substitutions, quotes, and spaces.
- Verify that arguments reach `Open3` separately and no shell is invoked.
- Run the test suite and explain any intentional compatibility changes.
```

## 3. Fix webhook SSRF

```text
Secure RailsNexus webhook delivery and `SettingsController#test_webhook` against SSRF.

Requirements:
- Permit only HTTPS by default, with an explicit development-only option for HTTP.
- Reject URLs containing credentials.
- Resolve the hostname before connecting.
- Reject loopback, private, link-local, multicast, unspecified, and reserved IPv4/IPv6 addresses.
- Specifically block cloud metadata destinations such as `169.254.169.254`.
- Prevent DNS rebinding by connecting only to the validated resolved address while preserving the original hostname for TLS and the Host header.
- Either reject redirects or revalidate every redirect destination.
- Add configurable allowed-host and denied-host lists.
- Apply the same validation to test webhooks and normal exception webhooks.
- Return safe error messages without leaking secrets.
- Add tests for localhost, private IPv4, IPv6 loopback, metadata IPs, redirects, invalid schemes, and a valid public HTTPS URL.
- Run all tests and document the new configuration.
```

## 4. Secure source-code viewing

```text
Harden RailsNexus source-code viewing and Git blame execution.

Requirements:
- Ensure `SourceCodeController` uses the global RailsNexus authentication.
- Resolve both `Rails.root` and the requested file with `File.realpath`.
- Verify containment using `Pathname#relative_path_from` or an equivalent path-component-aware method. Do not use string `start_with?`.
- Reject paths outside `Rails.root`, including sibling-prefix paths and symlink escapes.
- Pass the resolved validated path to all subsequent file operations.
- Cap `context_lines` to a safe range, such as 0–50.
- Replace backticks and interpolated Git commands with argument-array `Open3.capture3`.
- Do not invoke a shell.
- Handle missing Git repositories and malformed paths without raising a 500 error.
- Add tests for traversal, sibling-prefix paths, symlink escapes, filenames containing shell characters, and valid application files.
- Run the complete test suite.
```

## 5. Correct exception handling

```text
Refactor RailsNexus exception capture for modern Rails 8 applications.

Requirements:
- Stop generating `rescue_from Exception`.
- Use `StandardError`, or a narrower Rails-compatible exception boundary.
- Do not capture `SystemExit`, `SignalException`, `Interrupt`, `NoMemoryError`, or fatal VM errors.
- Preserve Rails' normal exception rendering and reporting behavior.
- Avoid mutating `request.parameters` while filtering sensitive values.
- Use Rails parameter-filtering APIs such as `ActiveSupport::ParameterFilter`.
- Recursively filter nested hashes and arrays.
- Ensure passwords, tokens, authorization headers, cookies, and configured filter parameters are never persisted.
- Update the install generator without duplicating handlers when run repeatedly.
- Add tests for filtered nested parameters, re-raised application errors, and fatal exceptions that must not be captured.
- Update installation documentation and run all tests.
```

## 6. Add database portability

```text
Make RailsNexus analytics database-independent across SQLite, PostgreSQL, and MySQL/MariaDB.

Requirements:
- Find MySQL-specific SQL such as `DATE_FORMAT`.
- Replace adapter-specific date grouping with portable Active Record logic or a clearly isolated adapter abstraction.
- Do not interpolate request parameters into SQL fragments.
- Preserve hourly and daily error-trend behavior.
- Review table-size, index-health, and database-statistics queries for adapter assumptions.
- Return unsupported data cleanly when a metric cannot be collected on an adapter.
- Add tests for SQLite, PostgreSQL, and MySQL/MariaDB where practical.
- Avoid loading an unbounded number of exception records into Ruby.
- Add a CI matrix covering supported databases.
- Update the README with the actual supported database capabilities.
- Run the relevant test matrix and report results.
```

## 7. Support Importmap and jsbundling cleanly

```text
Refactor RailsNexus asset distribution so it works cleanly in Rails 8 host applications using Importmap, jsbundling-rails with esbuild or Bun, or no JavaScript bundler.

Goals:
- The engine must remain mountable without modifying the host application's JavaScript entry point.
- Avoid forcing `importmap-rails` as a runtime dependency if the host does not otherwise use it.
- Prefer shipping a prebuilt, self-contained RailsNexus JavaScript bundle and CSS asset.
- Prevent duplicate Turbo and Stimulus application instances when the host already provides them.
- Keep RailsNexus Stimulus controllers namespaced.
- Support Propshaft and Sprockets.
- Ensure assets are fingerprinted and precompile correctly in production.
- Preserve Content Security Policy compatibility.
- Add dummy applications or test configurations representing Rails 8 with Importmap, Rails 8 with jsbundling/esbuild, Rails 8 with Propshaft, and Sprockets compatibility.
- Update the gemspec, engine initializers, layout, and documentation.
- Run production asset-precompilation tests for each supported configuration.
```

## 8. Perform the release-readiness pass

```text
Prepare `rails_nexus` for a secure RubyGems release after the functional fixes are complete.

Requirements:
- Add GitHub Actions CI for supported Ruby and Rails versions.
- Target Ruby 3.2, 3.3, 3.4, and 4.0 where dependencies support them.
- Test Rails 8.0 and 8.1.
- Include SQLite tests and appropriate PostgreSQL/MySQL service jobs.
- Run tests, RuboCop, Brakeman, and Bundler Audit.
- Add Dependabot configuration.
- Remove `.idea` from Git tracking and add it to `.gitignore`.
- Verify gem contents with `gem build` and `gem contents`.
- Ensure secrets, development databases, logs, and temporary backup files are excluded.
- Verify RubyGems MFA metadata and release metadata.
- Add security-reporting instructions through `SECURITY.md`.
- Update the changelog with security fixes without publishing exploit details.
- Do not publish the gem or create a release.
- Finish with a release checklist and identify anything still blocking publication.
```

## Optional single-pass master prompt

```text
Perform a security and release-readiness refactor of `tamiru/rails_nexus` based on the repository's current main branch.

Work incrementally in this order: fail-closed global authentication, missing controller authorization, backup shell-command safety, webhook SSRF prevention, source-code path and Git-command safety, Rails exception handling, database portability, asset compatibility, and CI/release hygiene.

Before editing, inspect the relevant implementation and tests. Keep each concern in a separate commit. Add regression tests before or alongside every fix. Do not publish the gem, create a GitHub release, or change public APIs unnecessarily. Preserve Rails 8 compatibility and support both Propshaft and Sprockets. At the end, run the complete available test and security-check suite, summarize every changed file, list any compatibility changes, and clearly identify unresolved release blockers.
```
