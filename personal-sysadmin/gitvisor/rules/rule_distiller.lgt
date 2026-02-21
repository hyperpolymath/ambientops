% SPDX-License-Identifier: AGPL-3.0-or-later
% Rule distillation - converting neural patterns to symbolic rules

:- object(rule_distiller).

    :- info([
        version is 1:0:0,
        author is 'hyperpolymath',
        date is 2025-12-29,
        comment is 'Distills neural patterns into fast symbolic rules'
    ]).

    :- public(distill_rule/2).
    :- mode(distill_rule(+compound, -compound), zero_or_one).
    :- info(distill_rule/2, [
        comment is 'Converts a neural pattern to a Logtalk rule',
        argnames is ['Pattern', 'Rule']
    ]).
    
    distill_rule(Pattern, Rule) :-
        % Neural layer detected pattern with confidence
        neural_pattern(Pattern, Confidence),
        Confidence > 0.85,
        % Convert to symbolic predicate
        pattern_to_predicate(Pattern, Predicate),
        % Validate against existing rules
        \+ conflicting_rule(Predicate),
        % Generate optimized rule
        compile_rule(Predicate, Rule).

    :- public(pattern_to_predicate/2).
    :- mode(pattern_to_predicate(+compound, -compound), zero_or_one).
    
    % Example: Rust repos without fuzzing have security issues
    pattern_to_predicate(
        pattern(rust_no_fuzz, [has_rust, no_fuzzing], security_risk),
        (repo_needs_fuzzing(R) :- repo_language(R, rust), \+ repo_has_fuzzing(R))
    ).
    
    % Example: Repos with many dependencies need dependabot
    pattern_to_predicate(
        pattern(deps_no_bot, [many_deps, no_dependabot], outdated_deps),
        (repo_needs_dependabot(R) :- repo_dependency_count(R, N), N > 5, \+ repo_has_dependabot(R))
    ).
    
    % Example: Public repos need security policy
    pattern_to_predicate(
        pattern(public_no_security, [is_public, no_security_md], vuln_reports_lost),
        (repo_needs_security_md(R) :- repo_visibility(R, public), \+ repo_has_file(R, 'SECURITY.md'))
    ).

    :- private(conflicting_rule/1).
    conflicting_rule(Rule) :-
        existing_rule(Existing),
        rules_conflict(Rule, Existing).

    :- private(compile_rule/2).
    compile_rule(Predicate, compiled(Predicate, ByteCode)) :-
        % Compile to optimized form for fast execution
        term_to_atom(Predicate, Atom),
        atom_codes(Atom, ByteCode).

:- end_object.
