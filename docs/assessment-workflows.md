# Assessment workflows

`check --project` validates one enabled project. `check --all` iterates enabled projects by stable ID and continues after project-quality/incomplete outcomes while retaining the greatest exit class. Storage failures abort through exit 4. Each project is staged, checked, published, recorded, and cleaned before the next begins. Human output is emitted per project; JSON batch output is accumulated and emitted once after all selected projects have terminal outcomes.
