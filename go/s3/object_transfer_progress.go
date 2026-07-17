// Progress reporting for multi-object copy/move sweeps. Item counts feed the
// determinate progress bar while byte counts keep speed/byte labels working.
package s3

import (
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// sumTransferEntrySizes totals entry sizes for byte-based progress labels.
func sumTransferEntrySizes(entries []types.Object) int64 {
	var total int64
	for _, entry := range entries {
		if entry.Size != nil && *entry.Size > 0 {
			total += *entry.Size
		}
	}
	return total
}

// advanceTransferTaskProgress records one finished entry: byte progress drives
// speed labels and item progress drives the determinate bar.
func advanceTransferTaskProgress(task objectTransferTask, entry types.Object) {
	if task.id == "" {
		return
	}
	task.advance(entry)
	AdvanceTransferItems(task.id, 1)
}

