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

	if m.session == nil || m.session.access == nil || m.session.access.writeback == nil {
		return false
	}
	return m.session.access.writeback.cancelTask(taskID)
}

func (m *manager) triggerQueuedTransfer(taskID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.session == nil || m.session.access == nil || m.session.access.writeback == nil {
		return false
	}
	return m.session.access.writeback.triggerTask(taskID)
}
