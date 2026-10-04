# Envoy Gateway on AKS: article package

- `envoy-gateway-medium-article.md`  the article (markdown, source of truth)
- `envoy-gateway-medium-article.html`  same article, self-contained, open in a browser to preview or copy from
- `images/`  8 figures, upload each one in Medium where the markdown has `![...](images/...)`
- `manifests/`  the full YAML for every step in the article

## Publishing on Medium
Medium has no tables and no markdown import, so:
1. Open the HTML file in a browser, select all, copy, paste into a new Medium story. Headings, bold, lists and links carry over.
2. Code blocks: select the pasted YAML and use Medium's code block button, or type three backticks on an empty line.
3. Images: upload each file from `images/` at the matching figure caption (the + button, then the image icon).
4. Long YAML reads better as a GitHub Gist or repo link than as an in-article block. Pushing `manifests/` to a public repo and linking it is the strongest way to show the implementation.
