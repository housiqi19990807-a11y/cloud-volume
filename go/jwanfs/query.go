// Query value helpers: QueryValues (a thin net/url.Values wrapper) and
// structToQueryValues (reflection-based struct → query encoder).
package jwanfs

import (
	"fmt"
	"net/url"
	"reflect"
	"strconv"
	"strings"
)

// QueryValues is a convenience wrapper around net/url.Values used by FGW API
// callers so they can pass either a url.Values or the output of
// structToQueryValues interchangeably.
type QueryValues struct {
	values url.Values
}

// makeQueryValues creates an empty QueryValues ready for Add calls.
func makeQueryValues() QueryValues {
	return QueryValues{values: url.Values{}}
}

// Add appends a key/value pair.
func (q QueryValues) Add(key, value string) {
	if q.values == nil {
		q.values = url.Values{}
	}
	q.values.Add(key, value)
}

// AsURLValues returns the underlying url.Values (nil-safe).
func (q QueryValues) AsURLValues() url.Values {
	if q.values == nil {
		return url.Values{}
	}
	return q.values
}

// mergeQueryValues combines multiple QueryValues into one. Nil entries are skipped.
func mergeQueryValues(values ...QueryValues) QueryValues {
	merged := makeQueryValues()
	for _, v := range values {
		for key, vs := range v.AsURLValues() {
			for _, item := range vs {
				merged.Add(key, item)
			}
		}
	}
	return merged
}

// structToQueryValues encodes a struct's `query:`-tagged fields into QueryValues.
// Zero values are omitted. Anonymous embedded structs are flattened.
func structToQueryValues(v any) QueryValues {
	values := url.Values{}
	appendStructToQueryValues(values, reflect.ValueOf(v))
	return QueryValues{values: values}
}

func appendStructToQueryValues(values url.Values, value reflect.Value) {
	if !value.IsValid() {
		return
	}
	for value.Kind() == reflect.Pointer {
		if value.IsNil() {
			return
		}
		value = value.Elem()
	}
	if value.Kind() != reflect.Struct {
		return
	}

	valueType := value.Type()
	for i := 0; i < value.NumField(); i++ {
		field := value.Field(i)
		fieldType := valueType.Field(i)
		if fieldType.PkgPath != "" {
			continue
		}

		if fieldType.Anonymous {
			appendStructToQueryValues(values, field)
			continue
		}

		tag := fieldType.Tag.Get("query")
		if tag == "" {
			continue
		}

		for field.Kind() == reflect.Pointer {
			if field.IsNil() {
				goto nextField
			}
			field = field.Elem()
		}

		if isZeroQueryField(field) {
			goto nextField
		}

		values.Add(tag, queryFieldString(field))
	nextField:
	}
}

func isZeroQueryField(v reflect.Value) bool {
	switch v.Kind() {
	case reflect.String:
		return v.Len() == 0
	case reflect.Bool:
		return !v.Bool()
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return v.Int() == 0
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		return v.Uint() == 0
	case reflect.Slice, reflect.Array:
		return v.Len() == 0
	case reflect.Interface:
		return v.IsNil()
	case reflect.Struct:
		return false
	default:
		return v.IsZero()
	}
}

func queryFieldString(v reflect.Value) string {
	switch v.Kind() {
	case reflect.String:
		return v.String()
	case reflect.Bool:
		return strconv.FormatBool(v.Bool())
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return strconv.FormatInt(v.Int(), 10)
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		return strconv.FormatUint(v.Uint(), 10)
	case reflect.Slice:
		if v.Type().Elem().Kind() == reflect.String {
			items := make([]string, v.Len())
			for i := 0; i < v.Len(); i++ {
				items[i] = v.Index(i).String()
			}
			return strings.Join(items, ",")
		}
	}
	return fmt.Sprint(v.Interface())
}

