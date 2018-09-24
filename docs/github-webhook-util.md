# GitHub Webhook Util

GitHub Webhook Util is a tool written in haskell that listens for GitHub
webhook events processes those events.

It requires a token to be able to check status events. In our case, since
both run on the hydra server, we use the same token.

It also requires setting up a webhook on the repositories you want to
collect data from.

Both credentials are loaded from an EnvironmentFile
by systemd that is deployed using nixops deployment keys.

## Secrets

A secret file needs to be created with the following format:

    GITHUB_SERVANT_SECRET=foo
    GITHUB_TOKEN=bar

The Servant secret is the one that should be configured in github webhook.
The token is the personal access token being used to query API.

## Setup

Setup consists of adding a webhook to the repository. This webhook needs
to have access to Status Data. Then both tokens should be place in
`static/github-webhook-util.secret`. After a deploy, the service should
start and nginx should be listening for github notification requests.

## Webhooks

### GitHub Status Event Data Collection

Any GitHub Status event will check if the commit attached to that status
has all statuses completed (Success or Failure, not pending or error). If
so, it will query some extra data about those statuses, mainly how long
each one took to complete from the time the first status check arrived.

It will then take that data and write it to influxDB to be viewed by
devops/developers with grafana.

## TODO

* Add integration to grab hydra phase metrics for all statuses and insert
them into influxDB as well.
* Integrate with the servant graphing utility for generating time lines of
hydra derivations.
* get PR metadata for commits if exists, so individual PR's can be graphed.
