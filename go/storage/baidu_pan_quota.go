// Baidu Pan quota discovery runs separately so bucket listing can render immediately.
package storage

import (
	"context"
	"fmt"
	"strings"

	xpanclient "github.com/lfhy/xpan/client"
	xpantypes "github.com/lfhy/xpan/types"
	xpanuser "github.com/lfhy/xpan/user"

	bridgelog "remote-storage/go/logging"
)

func (b baiduPanBackend) BucketQuota(
	_ context.Context,
	bucketName string,
) (BucketInfo, error) {
	name := strings.TrimSpace(bucketName)
	if name == "" {
		name = baiduPanBucketLabel(b.cfg)
	}
	bucket := BucketInfo{Name: name}
	bridgelog.Infof(
		"[storage/baidu-pan] quota request start bucket=%q profile=%q",
		bucket.Name,
		b.cfg.DisplayName,
	)
	quota, err := withBaiduPanClient(b.cfg, fetchBaiduPanQuota)
	if err != nil {
		bridgelog.Errorf(
			"[storage/baidu-pan] quota request failed bucket=%q err=%v",
			bucket.Name,
			err,
		)
		return bucket, err
	}
	if quota == nil {
		err := fmt.Errorf("empty response")
		bridgelog.Errorf(
			"[storage/baidu-pan] quota request failed bucket=%q err=%v",
			bucket.Name,
			err,
		)
		return bucket, err
	}
	bucket.QuotaBytes = int64(quota.Total)
	bucket.UsedBytes = int64(quota.Used)
	bucket.QuotaKnown = true
	bridgelog.Infof(
		"[storage/baidu-pan] quota request success bucket=%q total_bytes=%d used_bytes=%d",
		bucket.Name,
		bucket.QuotaBytes,
		bucket.UsedBytes,
	)
	return bucket, nil
}

func fetchBaiduPanQuota(client *xpanclient.Client) (*xpanuser.QuotaRes, error) {
	return client.Quota(&xpanuser.QuotaReq{
		Checkfree:   xpantypes.BoolIntTrue,
		Checkexpire: xpantypes.BoolIntTrue,
	})
}
