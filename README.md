# Bloggy

These are the sources of my blog "Lectern", hosted at [qducasse.github.io](https://qducasse.github.io). The site is built using [Hugo](https://gohugo.io/) and deployed with github-pages. The submodule `public` refers to the static files also stored on [github](https://github.com/QDucasse/qducasse.github.io) on which the github-pages deploys the site.

To add a new post, simply add a markdown file in `content/posts` with the correct tags:

```markdown
---
title: "Post title"
date: "YYYY-MM-DD"
tags: [
    "tag1",
    "tag2",
]
categories: [
    "Guide", 
    "Article"
]
---
```

Once the post is added, simply run `hugo` to generate the static files in `public`, then go to `public` and push the changes to deploy them!

```bash
$ hugo
$ cd public
$ git commit . -m "New post!"
$ git push
```

Don't forget to also commit/push the changes to this repository!