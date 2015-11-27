"use babel";

import {Emitter} from 'atom'

export default class Polling {
  initialize() {
    this.emitter = new Emitter
  }
  destroy() {
    clearTimeout(this._timeout)
  }
  poll() {
    this.emitter.emit('did-tick')
    this._timeout = setTimeout(this.poll.bind(this), this.interval)
  }
  start() {
    this.poll()
  }
  stop() {
    clearTimeout(this._timeout)
    this._timeout = null
  }
  forceIfStarted() {
    if (this._timeout) {
      this.poll()
    }
  }
  set(interval) {
    this.interval = interval
    if (this._timeout) {
      this.stop()
      this.start()
    }
  }
  onDidTick(cb) {
    this.emitter.on('did-tick', cb)
  }
}
