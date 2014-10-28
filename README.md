# Edit your RestoReady theme locally

[![Gem Version](https://badge.fury.io/rb/restoready_theme.svg)](http://badge.fury.io/rb/restoready_theme)

The RestoReady theme gem is a command line tool that lets you make live changes to themes on your RestoReady site.

It will watch your local folders for any changes in your theme (including adding and removing files) and will update your .restoready.com site to the latest changes.

You do not need to make changes to your default theme. You can leverage the theme preview feature of RestoReady
that allows you to view what an unpublished theme looks like on your RestoReady site.

# Requirements

This gem works with OS X with Ruby 1.9 and 2.x.

# Installation

To install the restoready_theme gem use 'gem install'.

```
gem install restoready_theme
```

or add this line in Gemfile and run `bundle install`

```
gem restoready_theme
```

to update to the latest version

```
gem update restoready_theme
```

to download the thème given in config

```
gem update restoready_theme
```

# Usage

Generate the config file. To choose the theme you want to edit, add `theme_id`.

```
theme configure api_key api_url site_url theme_id
```

Example of config.yml. You can use `:whitelist_files:` to specify files for upload. The `assets/`, `config/`,
`layouts/`, `snippets/`, `templates/` and `locales/`directories are included by
default.

You can also use `:ignore_files:` to exclude files from getting uploaded, for
example your `config/settings.html.liquid` or other configuration driven items

```yaml
---
:api_key: api_key
:api_url: https://demo.restoready.com
:site_url: https://demo.restoready.com
:theme_id: '1'
:whitelist_files:
- directoryToUpload/
- importantFile.txt
:ignore_files:
- config/settings.html.liquid
```

Upload a theme file

```
theme upload assets/layout.liquid
```

Remove a theme file

```
theme remove assets/layout.liquid
```

Completely replace theme assets with the local assets

```
theme replace
```

Watch the theme directory and upload any files as they change

```
theme watch
```

Open the site in the default browser

```
theme open
```

Bootstrap a new theme with [Starter](https://github.com/restoready/starter)

```
theme bootstrap api_key api_url site_url theme_name
```
