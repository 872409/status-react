(ns status-im.hardwallet.export-key
  (:require [status-im.utils.fx :as fx]
            [taoensso.timbre :as log]
            [status-im.hardwallet.common :as common]))

(fx/defn on-export-key-error
  {:events [:hardwallet.callback/on-export-key-error]}
  [{:keys [db] :as cofx} error]
  (log/debug "[hardwallet] export key error" error)
  (let [tag-was-lost? (= "Tag was lost." (:error error))]
    (cond tag-was-lost?
          (fx/merge cofx
                    {:db (assoc-in db [:hardwallet :pin :status] nil)}
                    (common/set-on-card-connected :wallet.accounts/generate-new-keycard-account))

          (re-matches common/pin-mismatch-error (:error error))
          (fx/merge cofx
                    {:db (update-in db [:hardwallet :pin] merge {:status       :error
                                                                 :enter-step   :export-key
                                                                 :puk          []
                                                                 :current      []
                                                                 :original     []
                                                                 :confirmation []
                                                                 :sign         []
                                                                 :error-label  :t/pin-mismatch})}
                    (common/hide-pair-sheet)
                    (common/get-application-info (common/get-pairing db) nil))

          :else
          (fx/merge cofx
                    (common/show-wrong-keycard-alert true)
                    (common/hide-pair-sheet)))))

(fx/defn on-export-key-success
  {:events [:hardwallet.callback/on-export-key-success]}
  [{:keys [db] :as cofx} pubkey]
  (let [callback-fn (get-in db [:hardwallet :on-export-success])]
    (fx/merge cofx
              {:dispatch (callback-fn pubkey)}
              (common/hide-pair-sheet))))
