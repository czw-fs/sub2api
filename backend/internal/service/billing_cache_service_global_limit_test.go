package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/config"
	"github.com/Wei-Shaw/sub2api/internal/pkg/usagestats"
	"github.com/stretchr/testify/require"
)

type globalDailyUsageLimitSettingsStub struct {
	values map[string]string
	err    error
	calls  int
}

func (s *globalDailyUsageLimitSettingsStub) GetMultiple(_ context.Context, keys []string) (map[string]string, error) {
	s.calls++
	if s.err != nil {
		return nil, s.err
	}
	out := make(map[string]string, len(keys))
	for _, key := range keys {
		out[key] = s.values[key]
	}
	return out, nil
}

type globalDailyUsageLimitUsageStub struct {
	actualCost float64
	err        error
	calls      int
	start      time.Time
	end        time.Time
}

func (s *globalDailyUsageLimitUsageStub) GetGlobalStats(_ context.Context, startTime, endTime time.Time) (*usagestats.UsageStats, error) {
	s.calls++
	s.start = startTime
	s.end = endTime
	if s.err != nil {
		return nil, s.err
	}
	return &usagestats.UsageStats{TotalActualCost: s.actualCost}, nil
}

func newBillingServiceForGlobalDailyUsageLimit(t *testing.T, settings *globalDailyUsageLimitSettingsStub, usage *globalDailyUsageLimitUsageStub) *BillingCacheService {
	t.Helper()
	svc := NewBillingCacheService(nil, nil, nil, nil, nil, nil, &config.Config{})
	t.Cleanup(svc.Stop)
	svc.SetGlobalDailyUsageLimitDependencies(settings, usage)
	return svc
}

func TestBillingCacheService_CheckGlobalDailyUsageLimitDisabledSkipsUsageLookup(t *testing.T) {
	settings := &globalDailyUsageLimitSettingsStub{values: map[string]string{
		SettingKeyGlobalDailyUsageLimitEnabled: "false",
		SettingKeyGlobalDailyUsageLimitUSD:     "80",
	}}
	usage := &globalDailyUsageLimitUsageStub{actualCost: 100}
	svc := newBillingServiceForGlobalDailyUsageLimit(t, settings, usage)

	require.NoError(t, svc.checkGlobalDailyUsageLimit(context.Background()))
	require.Equal(t, 1, settings.calls)
	require.Equal(t, 0, usage.calls)
}

func TestBillingCacheService_CheckGlobalDailyUsageLimitAllowsUnderLimit(t *testing.T) {
	settings := &globalDailyUsageLimitSettingsStub{values: map[string]string{
		SettingKeyGlobalDailyUsageLimitEnabled: "true",
		SettingKeyGlobalDailyUsageLimitUSD:     "80",
	}}
	usage := &globalDailyUsageLimitUsageStub{actualCost: 79.99}
	svc := newBillingServiceForGlobalDailyUsageLimit(t, settings, usage)

	require.NoError(t, svc.checkGlobalDailyUsageLimit(context.Background()))
	require.Equal(t, 1, usage.calls)
	require.InDelta(t, 24*time.Hour, usage.end.Sub(usage.start), float64(time.Minute))
}

func TestBillingCacheService_CheckGlobalDailyUsageLimitRejectsAtLimit(t *testing.T) {
	settings := &globalDailyUsageLimitSettingsStub{values: map[string]string{
		SettingKeyGlobalDailyUsageLimitEnabled: "true",
		SettingKeyGlobalDailyUsageLimitUSD:     "80",
	}}
	usage := &globalDailyUsageLimitUsageStub{actualCost: 80}
	svc := newBillingServiceForGlobalDailyUsageLimit(t, settings, usage)

	require.ErrorIs(t, svc.checkGlobalDailyUsageLimit(context.Background()), ErrGlobalDailyUsageLimitExceeded)
}

func TestBillingCacheService_CheckGlobalDailyUsageLimitFailOpenOnLookupErrors(t *testing.T) {
	settings := &globalDailyUsageLimitSettingsStub{values: map[string]string{
		SettingKeyGlobalDailyUsageLimitEnabled: "true",
		SettingKeyGlobalDailyUsageLimitUSD:     "80",
	}}
	usage := &globalDailyUsageLimitUsageStub{err: errors.New("db down")}
	svc := newBillingServiceForGlobalDailyUsageLimit(t, settings, usage)

	require.NoError(t, svc.checkGlobalDailyUsageLimit(context.Background()))
}
