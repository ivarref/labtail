# labtail

Are you tired of clicking around in the GitLab Web UI to see the output of pipelines
and jobs? If so, this tool is for you.

`labtail` will:

* Show the output of the most recent GitLab pipeline job.
* Keep looking for new pipelines and show the output.
* Optionally commit and push your changes if `--push` is given*.

\* Useful for small edits to `.gitlab-ci.yml`.

## Installation

```
curl -LsSf https://raw.githubusercontent.com/ivarref/labtail/e3bb20987544619810ca03475529cbc0228306c4/labtail.sh -O \
&& chmod +x ./labtail.sh \
&& mv ./labtail.sh "$HOME/.local/bin/labtail"
```

`labtail` requires [glab](https://docs.gitlab.com/editor_extensions/gitlab_cli/),
the GitLab CLI tool, to be installed and properly authenticated to your
GitLab remote. [jq](https://jqlang.org/) is also required.


## My old workflow

* Make an actual change and save the file.
* Alt-0: go to git changes.
* Space: mark file to commit.
* Alt-P: push marked changes.
* Alt-P again: yes, push those changes.
* Alt-tab to browser.
* Ctrl-R: refresh the pipeline.
* Click the pipeline.
* Click the job.
* Wait for the output to appear, maybe scroll down.
* Whoops, the line should start with `- |` not `- >`.
* Alt-tab to IDE. Go to start.

## My new workflow

* Run `labtail --push` in a terminal.
* Make changes and save files.
* Breathe and enjoy life*.

\* I may be still writing bash in YAML occasionally, but hey.

## Usage

```bash
labtail
```

Or automatically push changes:

```bash
labtail --push
```
