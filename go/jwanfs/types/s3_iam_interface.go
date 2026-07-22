// AKSK permission types used by auth-info responses.
package types

import "strings"

// AKSKAction is a permission action string (read/write/list).
type AKSKAction = string

const (
	AKSKActionWrite             AKSKAction = "write"
	AKSKActionRead              AKSKAction = "read"
	AKSKActionList              AKSKAction = "list"
	AKSKObjectStorageBucketRoot            = "/buckets"
)

// AKSKAdminActions is the full admin action set.
var AKSKAdminActions = []AKSKAction{AKSKActionWrite, AKSKActionRead, AKSKActionList}

// AKSKBucketPermission is a single path-scoped permission rule.
type AKSKBucketPermission struct {
	Path    string       `json:"Path,omitempty"`
	Actions []AKSKAction `json:"Actions,omitempty"`
}

// CanDo reports whether the permission covers targetPath for all actions.
func (p AKSKBucketPermission) CanDo(targetPath string, action ...AKSKAction) bool {
	if p.Path == "" {
		return false
	}
	if targetPath != p.Path && !strings.HasPrefix(targetPath, p.Path+"/") {
		return false
	}
	return p.CheckAction(action...)
}

// CheckAction reports whether all requested actions are allowed.
func (p AKSKBucketPermission) CheckAction(action ...AKSKAction) bool {
	if len(p.Actions) == 0 || len(action) == 0 {
		return true
	}
	allowed := make(map[AKSKAction]struct{}, len(p.Actions))
	for _, a := range p.Actions {
		allowed[a] = struct{}{}
	}
	for _, ac := range action {
		if _, ok := allowed[ac]; !ok {
			return false
		}
	}
	return true
}

