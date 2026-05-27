package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

// Paging bridge methods expose continuation-token listing for long directories and trash views.
type objectPageArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                            `json:"bucket"`
	Prefix    string                            `json:"prefix"`
	NextToken string                            `json:"nextToken"`
	PageSize  int32                             `json:"pageSize"`
}

type trashPageArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                            `json:"bucket"`
	NextToken string                            `json:"nextToken"`
	PageSize  int32                             `json:"pageSize"`
}

func listObjectPage(args json.RawMessage) (any, error) {
	var input objectPageArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return s3ops.ListObjectsPage(
		input.Config,
		input.Bucket,
		input.Prefix,
		input.NextToken,
		input.PageSize,
	)
}

func listTrashPage(args json.RawMessage) (any, error) {
	var input trashPageArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return s3ops.ListTrashPage(
		input.Config,
		input.Bucket,
		input.NextToken,
		input.PageSize,
	)
}
