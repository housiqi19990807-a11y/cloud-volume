// FGW temporary-token request/response types.
package types

// UserTempTokenReq creates or updates a temporary AKSK.
type UserTempTokenReq struct {
	ExpireTime      int64  `json:"ExpireTime"`
	Update          bool   `json:"Update"`
	Ak              string `json:"Ak"`
	Sk              string `json:"Sk"`
	Role            string `json:"Role,omitempty"`
	Actions         string `json:"Actions,omitempty"`
	Resources       string `json:"Resources,omitempty"`
	Description     string `json:"Description,omitempty"`
	ParentAccessKey string `json:"ParentAccessKey,omitempty"`
}

// UserTempTokenAKSKRes is the returned temporary credential set.
type UserTempTokenAKSKRes struct {
	AccessKeys string
	SecretKeys string
	Expiretion string
}

