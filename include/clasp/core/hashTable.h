/*
    File: hashTable.h
*/

/*
Copyright (c) 2014, Christian E. Schafmeister
 
CLASP is free software; you can redistribute it and/or
modify it under the terms of the GNU Library General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.
 
See directory 'clasp/licenses' for full details.
 
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
/* -^- */
#ifndef	_core_HashTable_H
#define _core_HashTable_H

#include <clasp/core/foundation.h>
#include <clasp/core/object.h>
#include <clasp/core/vectorObjects.fwd.h>
#include <clasp/core/corePackage.fwd.h>


namespace core
{

    extern bool DebugHashTable;

    HashTable_mv af_make_hash_table(T_sp test, Fixnum_sp size, Number_sp rehash_size, DoubleFloat_sp orehash_threshold);



    FORWARD(HashTable);
    class HashTable_O : public T_O
    {
        struct metadata_bootstrap_class {};

	LISP_BASE1(T_O);
	LISP_VIRTUAL_CLASS(core,ClPkg,HashTable_O,"HashTable");
	void archiveBase(SNode_sp node);

	HashTable_O() : _InitialSize(4)
                      , _RehashSize(_Nil<Number_O>())
                      , _RehashThreshold(1.2)
                      , _HashTable(_Nil<VectorObjects_O>())
                      , _HashTableCount(0) {};
	virtual ~HashTable_O() {};
//	DEFAULT_CTOR_DTOR(HashTable_O);
	friend class HashTableEq_O;
	friend class HashTableEql_O;
	friend class HashTableEqual_O;
	friend class HashTableEqualp_O;
	friend T_mv af_maphash(T_sp function_desig, HashTable_sp hash_table);
	friend T_mv af_clrhash(HashTable_sp hash_table );

    GCPRIVATE: // instance variables here
	uint		_InitialSize;
	Number_sp	_RehashSize;
	double		_RehashThreshold;
	VectorObjects_sp _HashTable;
	uint		_HashTableCount;
//	uint		_EntryCount;
#ifdef USE_MPS
        mps_ld_s        _LocationDependencyTracker;
#endif        

    public:
	static HashTable_sp create(T_sp test); // set everything up with defaults

    public:

	static void sxhash_eq(HashGenerator& running_hash, T_sp obj, LocationDependencyPtrT);
	static void sxhash_eql(HashGenerator& running_hash, T_sp obj, LocationDependencyPtrT);
	static void sxhash_equal(HashGenerator& running_hash, T_sp obj, LocationDependencyPtrT);
	static void sxhash_equalp(HashGenerator& running_hash, T_sp obj, LocationDependencyPtrT );
    private:
	void setup(uint sz, Number_sp rehashSize, double rehashThreshold );
	uint resizeEmptyTable(uint sz);
	uint calculateHashTableCount() const;
        /*! If findKey is defined then search it as you rehash and return resulting keyValuePair CONS */
	Cons_sp rehash(bool expandTable, T_sp findKey );
	
    public: // Functions here
        virtual bool equalp(T_sp other) const;

	/*! See CLHS */
	virtual T_sp hashTableTest() const {SUBIMP();};
	
	/*! Return a count of the number of keys */
	uint hashTableCount() const;
        size_t size() { return this->hashTableCount(); };

	virtual Number_sp hashTableRehashSize() const { return this->_RehashSize;};

	double hashTableRehashThreshold() const { return this->_RehashThreshold;};

	uint hashTableSize() const;

	virtual int sxhashKey(T_sp key, int bound, bool willAddKey ) const;
	virtual bool keyTest(T_sp entryKey, T_sp searchKey) const;

        /*! I'm not sure I need this and tableRef */
        Cons_sp bucketsFind(T_sp key) const;
        /*! I'm not sure I need this and bucketsFind */
        Cons_sp tableRef(T_sp key);
	Cons_sp findAssoc(uint index, T_sp searchKey) const;

        /*! Return true if the key is within the hash table */
        bool contains(T_sp key);

        /*! Return the key/value pair in a CONS if found or NIL if not */
        Cons_sp find(T_sp key);

	T_mv gethash(T_sp key, T_sp defaultValue = _Nil<T_O>() ) ;
	int hashIndex(T_sp key) const;

	T_sp hash_table_setf_gethash(T_sp key, T_sp value);
        void setf_gethash(T_sp key, T_sp val) { this->hash_table_setf_gethash(key,val);};

	void clrhash();

	bool remhash(T_sp key);

	string __repr__() const;

	string hash_table_dump() const;

	void lowLevelMapHash(KeyValueMapper* mapper) const;

	void mapHash(std::function<void(T_sp, T_sp)> const& fn);
        void maphash(std::function<void(T_sp,T_sp)> const& fn) { this->mapHash(fn); };

        /*! maps function across a hash table until the function returns false */
	void terminatingMapHash(std::function<bool(T_sp, T_sp)> const& fn);

	/*! Return the number of entries in the HashTable Vector0 */
	int hashTableNumberOfHashes() const;
	/*! Return the start of the alist in the HashTable Vector0 at hash value */
	Cons_sp hashTableAlistAtHash(int hash) const;

        string keysAsString();
    };


    HashTable_mv af_make_hash_table(T_sp test, Fixnum_sp size, Number_sp rehash_size, DoubleFloat_sp orehash_threshold);


}; /* core */

TRANSLATE(core::HashTable_O);

#endif /* _core_HashTable_H */