import { hilog } from '@kit.PerformanceAnalysisKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG: string = 'HoldingHandService';
const HOLDING_HAND_COMMIT_DELAY_MS: number = 180;

export enum HoldingHandState {
  NOT_HELD = 0,
  LEFT_HAND_HELD = 1,
  RIGHT_HAND_HELD = 2,
  BOTH_HANDS_HELD = 3,
  UNKNOWN_STATUS = 16
}

export class HoldingHandService {
  private static instance: HoldingHandService | null = null;

  private listeners: ((status: HoldingHandState) => void)[] = [];
  private subscribed: boolean = false;
  private capabilityAvailable: boolean = true;
  private status: HoldingHandState = HoldingHandState.UNKNOWN_STATUS;
  private pendingStatus: HoldingHandState = HoldingHandState.UNKNOWN_STATUS;
  private commitTimerId: number = -1;
  private callback: Callback<motion.HoldingHandStatus> = (data: motion.HoldingHandStatus) => {
    this.handleRawStatus(data as number);
  };

  private constructor() {
  }

  static getInstance(): HoldingHandService {
    if (HoldingHandService.instance === null) {
      HoldingHandService.instance = new HoldingHandService();
    }
    return HoldingHandService.instance;
  }

  addListener(listener: (status: HoldingHandState) => void): void {
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] === listener) {
        try {
          listener(this.status);
        } catch (_) {
        }
        return;
      }
    }
    this.listeners.push(listener);
    this.ensureSubscribed();
    try {
      listener(this.status);
    } catch (_) {
    }
  }

  removeListener(listener: (status: HoldingHandState) => void): void {
    const next: ((status: HoldingHandState) => void)[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
    if (this.listeners.length === 0) {
      this.clearCommitTimer();
      this.unsubscribe();
    }
  }

  getStatus(): HoldingHandState {
    return this.status;
  }

  isCapabilityAvailable(): boolean {
    return this.capabilityAvailable;
  }

  private ensureSubscribed(): void {
    if (this.subscribed || !this.capabilityAvailable) {
      return;
    }
    try {
      motion.on('holdingHandChanged', this.callback);
      this.subscribed = true;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      if (error !== undefined && error !== null && error.code === 801) {
        this.capabilityAvailable = false;
        this.status = HoldingHandState.UNKNOWN_STATUS;
        hilog.info(0x0000, TAG, 'Holding hand capability unsupported on current device');
      } else {
        hilog.error(0x0000, TAG, 'Subscribe holdingHandChanged failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  private unsubscribe(): void {
    if (!this.subscribed) {
      return;
    }
    try {
      motion.off('holdingHandChanged', this.callback);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Unsubscribe holdingHandChanged failed: %{public}s', JSON.stringify(err));
    } finally {
      this.subscribed = false;
    }
  }

  private handleRawStatus(rawStatus: number): void {
    const nextStatus: HoldingHandState = this.normalizeStatus(rawStatus);
    if (nextStatus === this.status && this.commitTimerId < 0) {
      return;
    }
    this.pendingStatus = nextStatus;
    this.clearCommitTimer();
    this.commitTimerId = setTimeout(() => {
      this.commitTimerId = -1;
      if (this.status === this.pendingStatus) {
        return;
      }
      this.status = this.pendingStatus;
      this.notifyListeners();
    }, HOLDING_HAND_COMMIT_DELAY_MS);
  }

  private normalizeStatus(rawStatus: number): HoldingHandState {
    switch (rawStatus) {
      case HoldingHandState.NOT_HELD:
      case HoldingHandState.LEFT_HAND_HELD:
      case HoldingHandState.RIGHT_HAND_HELD:
      case HoldingHandState.BOTH_HANDS_HELD:
      case HoldingHandState.UNKNOWN_STATUS:
        return rawStatus as HoldingHandState;
      default:
        return HoldingHandState.UNKNOWN_STATUS;
    }
  }

  private clearCommitTimer(): void {
    if (this.commitTimerId < 0) {
      return;
    }
    clearTimeout(this.commitTimerId);
    this.commitTimerId = -1;
  }

  private notifyListeners(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i](this.status);
      } catch (_) {
      }
    }
  }
}
