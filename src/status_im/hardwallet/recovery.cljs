(ns status-im.hardwallet.recovery
  (:require [status-im.ui.screens.navigation :as navigation]
            [status-im.utils.datetime :as utils.datetime]
            [status-im.utils.fx :as fx]
            [taoensso.timbre :as log]
            [status-im.hardwallet.common :as common]
            status-im.hardwallet.fx
            [status-im.ui.components.bottom-sheet.core :as bottom-sheet]))

(fx/defn pair* [_ password]
  {:hardwallet/pair {:password password}})

(fx/defn pair
  {:events [:hardwallet/pair]}
  [{:keys [db] :as cofx}]
  (let [{:keys [password]} (get-in cofx [:db :hardwallet :secrets])
        card-connected?    (get-in db [:hardwallet :card-connected?])]
    (fx/merge cofx
              (common/set-on-card-connected :hardwallet/pair)
              (if card-connected?
                (pair* password)
                (common/show-pair-sheet {})))))

(fx/defn pair-code-next-button-pressed
  {:events [:keycard.onboarding.pair.ui/input-submitted
            :hardwallet.ui/pair-code-next-button-pressed
            :keycard.onboarding.pair.ui/next-pressed]}
  [{:keys [db] :as cofx}]
  (let [pairing (get-in db [:hardwallet :secrets :pairing])
        paired-on (get-in db [:hardwallet :secrets :paired-on] (utils.datetime/timestamp))]
    (fx/merge cofx
              (if pairing
                {:db (-> db
                         (assoc-in [:hardwallet :setup-step] :import-multiaccount)
                         (assoc-in [:hardwallet :secrets :paired-on] paired-on))}
                (pair)))))

(fx/defn load-pair-screen
  [{:keys [db] :as cofx}]
  (log/debug "[hardwallet] load-pair-screen")
  (fx/merge cofx
            {:db (-> db
                     (assoc-in [:hardwallet :setup-step] :pair))
             :dispatch [:bottom-sheet/hide-sheet]}
            (common/listen-to-hardware-back-button)
            (navigation/navigate-to-cofx :keycard-recovery-pair nil)))

(fx/defn keycard-storage-selected-for-recovery
  {:events [:recovery.ui/keycard-storage-selected]}
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db (assoc-in db [:hardwallet :flow] :recovery)}
            (navigation/navigate-to-cofx :keycard-recovery-enter-mnemonic nil)))

(fx/defn start-import-flow
  {:events [:hardwallet/recover-with-keycard-pressed]}
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db                           (assoc-in db [:hardwallet :flow] :import)
             :hardwallet/check-nfc-enabled nil}
            (bottom-sheet/hide-bottom-sheet)
            (navigation/navigate-to-cofx :keycard-recovery-intro nil)))

(fx/defn access-key-pressed
  {:events [:multiaccounts.recover.ui/recover-multiaccount-button-pressed]}
  [_]
  {:dispatch [:bottom-sheet/show-sheet :recover-sheet]})

(fx/defn recovery-keycard-selected
  {:events [:recovery.ui/keycard-option-pressed]}
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db                           (assoc-in db [:hardwallet :flow] :recovery)
             :hardwallet/check-nfc-enabled nil}
            (navigation/navigate-to-cofx :keycard-onboarding-intro nil)))

(fx/defn begin-setup-pressed
  {:events [:keycard.onboarding.intro.ui/begin-setup-pressed
            :keycard.recovery.intro.ui/begin-recovery-pressed]}
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db (-> db
                     (update :hardwallet
                             dissoc :secrets :card-state :multiaccount-wallet-address
                             :multiaccount-whisper-public-key
                             :application-info)
                     (assoc-in [:hardwallet :setup-step] :begin)
                     (assoc-in [:hardwallet :pin :on-verified] nil))}
            (common/set-on-card-connected :hardwallet/get-application-info)
            (common/set-on-card-read :hardwallet/check-card-state)
            (common/show-pair-sheet {})))

(fx/defn recovery-success-finish-pressed
  {:events [:keycard.recovery.success/finish-pressed]}
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db (update db :hardwallet dissoc
                         :multiaccount-wallet-address
                         :multiaccount-whisper-public-key)}
            (navigation/navigate-to-cofx :welcome nil)))

(fx/defn recovery-no-key
  {:events [:keycard.recovery.no-key.ui/generate-key-pressed]}
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db                           (assoc-in db [:hardwallet :flow] :create)
             :hardwallet/check-nfc-enabled nil}
            (navigation/navigate-to-cofx :keycard-onboarding-intro nil)))
