% SPDX-License-Identifier: AGPL-3.0-or-later
% gitvisor CI/CD Rules - Logtalk implementation

:- object(cicd_rules).

    :- info([
        version is 1:0:0,
        author is 'hyperpolymath',
        date is 2025-12-29,
        comment is 'Core CI/CD rules for gitvisor'
    ]).

    %% DECLARATIVE RULES (what should be true)
    
    :- public(repo_must_have/2).
    :- mode(repo_must_have(+atom, +atom), zero_or_more).
    :- info(repo_must_have/2, [
        comment is 'Declares files that a repo must have'
    ]).
    
    repo_must_have(Repo, 'dependabot.yml') :-
        repo_uses_dependencies(Repo).
    repo_must_have(Repo, 'codeql.yml') :-
        repo_has_code(Repo).
    repo_must_have(Repo, 'SECURITY.md') :-
        repo_is_public(Repo).
    repo_must_have(Repo, 'justfile') :-
        true.  % All repos need a justfile
    repo_must_have(Repo, 'STATE.scm') :-
        true.  % All repos need state tracking

    %% PREVENTIVE RULES (stop before it happens)
    
    :- public(block_commit_if/2).
    :- mode(block_commit_if(+compound, -atom), zero_or_more).
    
    block_commit_if(Commit, typescript_detected) :-
        commit_adds_file(Commit, File),
        file_extension(File, '.ts').
    block_commit_if(Commit, typescript_detected) :-
        commit_adds_file(Commit, File),
        file_extension(File, '.tsx').
    block_commit_if(Commit, go_detected) :-
        commit_adds_file(Commit, File),
        file_extension(File, '.go').
    block_commit_if(Commit, makefile_detected) :-
        commit_adds_file(Commit, File),
        file_name(File, 'Makefile').
    block_commit_if(Commit, python_detected) :-
        commit_adds_file(Commit, File),
        file_extension(File, '.py'),
        \+ is_saltstack_file(File).
    block_commit_if(Commit, npm_detected) :-
        commit_adds_file(Commit, File),
        file_name(File, 'package-lock.json').
    block_commit_if(Commit, secret_detected) :-
        commit_content_matches(Commit, Pattern),
        secret_pattern(Pattern).

    %% CURATIVE RULES (fix after detection)
    
    :- public(auto_fix/2).
    :- mode(auto_fix(+atom, +atom), zero_or_one).
    
    auto_fix(Repo, unpinned_actions) :-
        find_unpinned_actions(Repo, Actions),
        Actions \== [],
        pin_actions_to_sha(Repo, Actions).
    auto_fix(Repo, missing_permissions) :-
        find_workflows_without_permissions(Repo, Workflows),
        Workflows \== [],
        add_permissions(Repo, Workflows, 'read-all').
    auto_fix(Repo, missing_spdx) :-
        find_files_without_spdx(Repo, Files),
        Files \== [],
        add_spdx_headers(Repo, Files).

    %% HELPER PREDICATES
    
    :- private(is_saltstack_file/1).
    is_saltstack_file(File) :-
        (   sub_atom(File, _, _, _, '/salt/')
        ;   sub_atom(File, _, _, _, '/pillar/')
        ;   sub_atom(File, _, _, _, '/states/')
        ;   sub_atom(File, _, _, _, '/_modules/')
        ;   sub_atom(File, _, _, _, '/_states/')
        ).

    :- private(secret_pattern/1).
    secret_pattern('(?i)api[_-]?key').
    secret_pattern('(?i)secret[_-]?key').
    secret_pattern('(?i)password\\s*=').
    secret_pattern('(?i)token\\s*=').
    secret_pattern('ghp_[a-zA-Z0-9]{36}').
    secret_pattern('sk-[a-zA-Z0-9]{48}').

:- end_object.
