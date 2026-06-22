// Mount task queue exports let the bridge control delayed writeback items from Flutter.
package mount

// CancelQueuedTransfer cancels a pending delayed-writeback task if it still belongs to the mount layer.
func CancelQueuedTransfer(taskID string) bool {
	return globalManager.cancelQueuedTransfer(taskID)
}

// TriggerQueuedTransfer forces a pending delayed-writeback task to upload immediately.
func TriggerQueuedTransfer(taskID string) bool {
	return globalManager.triggerQueuedTransfer(taskID)
}

func (m *manager) cancelQueuedTransfer(taskID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, session := range m.sessions {
		if session.access == nil || session.access.writeback == nil {
			continue
		}
		if session.access.writeback.cancelTask(taskID) {
			return true
		}
	}
	return false
}

func (m *manager) triggerQueuedTransfer(taskID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, session := range m.sessions {
		if session.access == nil || session.access.writeback == nil {
			continue
		}
		if session.access.writeback.triggerTask(taskID) {
			return true
		}
	}
	return false
}
