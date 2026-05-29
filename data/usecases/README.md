# Use-Case Data Folder

This folder stores data that belongs to a specific country, crop, and use-case
implementation.

Use this pattern:

```bash
data/usecases/useCase_<Country>_<UseCaseName>/<Crop>/
```

Examples:

```bash
data/usecases/useCase_Kenya_Example/Maize/DSSAT/
```

Country-wide climate forecast inputs and outputs stay in `data/<ISO3>/`.
Use-case DSSAT templates, generated DSSAT run folders, crop-model results, and
curation files stay here.
