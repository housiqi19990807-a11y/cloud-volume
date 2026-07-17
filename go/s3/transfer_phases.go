// Transfer sweep progress phases and helpers shared by copy/move/delete code.
package s3

// Progress phases for multi-object sweeps. Copy phases and source-cleanup
// phases are planned separately so their totals can coexist (trash moves)
// without double-counting a repeated enumeration of the same tree.
const (
	transferPhaseCopy   = "copy"
	transferPhaseDelete = "delete"
)

